"""Ingestão CVDW -> bronze (Postgres). Por objeto: pagina a API, upsert idempotente,
snapshot do dia e marca de controle. Falha num objeto não derruba os demais.

  python ingestao.py --full [--criar-tabelas]
  python ingestao.py --incremental [--objetos reservas,leads]
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Sequence

import psycopg

from config.settings import (
    ConfigAPI,
    ConfigPostgres,
    Objeto,
    carregar_config_api,
    carregar_config_pg,
    carregar_objetos,
)
from cvdw import db
from cvdw.api import ClienteCVDW
from cvdw.db import (
    COL_DADOS_BRUTOS,
    COL_EXTRACAO,
    COL_HASH,
    COL_PAGINA,
    COL_TECNICA,
)
from cvdw.log import configurar_logging, get_logger
from cvdw.tipos import bucket_pg, hash_linha, nome_coluna, normalizar_para_sql, repr_para_hash

log = get_logger("ingestao")

RAIZ = Path(__file__).resolve().parent
BRONZE_SQL = RAIZ / "sql" / "bronze" / "bronze.sql"

# Colunas de metadados que não vêm da API.
_META = {COL_TECNICA, COL_HASH, COL_EXTRACAO, COL_PAGINA, COL_DADOS_BRUTOS}


def montar_linha(
    registro: dict[str, Any],
    colunas_fonte: Sequence[tuple[str, str]],
    tem_dados_brutos: bool,
    data_extracao: datetime,
    pagina: int,
) -> tuple[list[Any], str]:
    """Constrói (valores_para_insert, hash) de um registro.

    Mapeia cada coluna do banco à chave da API via nome_coluna() — chaves extras
    da API (drift) são ignoradas; colunas ausentes no registro viram NULL.
    """
    from psycopg.types.json import Json  # import local: só usado aqui

    mapeado = {nome_coluna(k): v for k, v in registro.items()}

    valores: list[Any] = []
    partes_hash: list[str] = []
    for nome, data_type in colunas_fonte:
        bruto = mapeado.get(nome)
        bucket = bucket_pg(data_type)
        valores.append(normalizar_para_sql(bruto, bucket))
        partes_hash.append(repr_para_hash(bruto, bucket))

    if tem_dados_brutos:
        valores.append(Json(registro))
        partes_hash.append(repr_para_hash(registro, "jsonb"))

    h = hash_linha(partes_hash)
    # Ordem final = fonte (+ dados_brutos) + _hash_linha + _data_extracao + _pagina
    valores.extend([h, data_extracao, pagina])
    return valores, h


def _colunas_insert(
    colunas_fonte: Sequence[tuple[str, str]], tem_dados_brutos: bool
) -> list[str]:
    """Lista de colunas, na ordem usada por montar_linha()."""
    nomes = [c for c, _ in colunas_fonte]
    if tem_dados_brutos:
        nomes.append(COL_DADOS_BRUTOS)
    nomes.extend([COL_HASH, COL_EXTRACAO, COL_PAGINA])
    return nomes


def ingerir_objeto(
    conn: psycopg.Connection,
    cliente: ClienteCVDW,
    cfg_api: ConfigAPI,
    schema: str,
    obj: Objeto,
    modo: str,
    inicio_execucao: datetime,
) -> int:
    """Ingere um objeto inteiro (paginação + upsert + snapshot + controle)."""
    tabela = obj.nome_logico
    if not db.tabela_existe(conn, schema, tabela):
        raise RuntimeError(
            f"Tabela {schema}.{tabela} não existe. Gere e aplique sql/bronze/bronze.sql "
            f"(ou rode com --criar-tabelas)."
        )

    colunas_db = db.colunas_tabela(conn, schema, tabela)
    colunas_fonte = [(n, t) for n, t in colunas_db if n not in _META]
    tem_dados_brutos = any(n == COL_DADOS_BRUTOS for n, _ in colunas_db)
    chave = db.chave_upsert(conn, schema, tabela)
    if not chave:
        raise RuntimeError(
            f"Índice único ux_{tabela}_chave não encontrado em {schema}.{tabela}."
        )

    colunas_insert = _colunas_insert(colunas_fonte, tem_dados_brutos)

    data_extracao = datetime.now(timezone.utc)
    # Espelho: esta execução é a leitura completa que remove o que a origem apagou.
    espelhar = _espelho_vencido(conn, cfg_api, schema, obj, modo, data_extracao)
    leitura_anterior = db.ler_leitura_completa(conn, schema, tabela) if espelhar else None

    # Data de referência (modo incremental). A leitura de espelho ignora a janela.
    a_partir = (None if espelhar
                else _data_referencia_incremental(conn, cfg_api, schema, obj, modo))
    if modo == "incremental":
        if espelhar:
            log.info("[%s] espelho=true: leitura completa para remover o que a origem apagou",
                     tabela)
        elif obj.sempre_full:
            log.info("[%s] sempre_full=true — recarga completa dentro do incremental",
                     tabela)
        elif a_partir:
            log.info("[%s] incremental a_partir_data_referencia=%s", tabela, a_partir)

    total = 0
    drift_avisado = False

    # Leitura de espelho: confere se a leitura trouxe tudo o que a origem declara ter. A
    # paginação do CVDW repete e pula registros na fronteira entre páginas quando muitos têm a
    # mesma data de modificação (carga em lote, R32), e os pulados são sempre os mesmos para o
    # mesmo tamanho de página: duas leituras iguais não provam que o registro saiu da origem.
    # Por isso a limpeza só roda sobre uma leitura que fechou com o total da origem, relida com
    # outros tamanhos de página enquanto não fechar.
    total_origem = cliente.total_registros_origem(obj.path, obj.base) if espelhar else None
    tamanhos = _tamanhos_de_leitura(cfg_api.registros_por_pagina) if espelhar else [None]
    posicoes_chave = [colunas_insert.index(c) for c in chave] if espelhar else []
    vistos: set[tuple] = set()
    fechou = False

    for tentativa, tamanho in enumerate(tamanhos, start=1):
        desta_leitura: set[tuple] = set()
        repetidas = 0
        for pagina, registros in cliente.paginar(obj.path, a_partir, obj.base, tamanho):
            if not registros:
                continue
            if not drift_avisado:
                drift_avisado = _avisar_drift(tabela, registros[0], colunas_fonte,
                                              tem_dados_brutos)
            linhas = [
                montar_linha(reg, colunas_fonte, tem_dados_brutos, data_extracao, pagina)[0]
                for reg in registros
            ]
            db.bulk_upsert(conn, schema, tabela, colunas_insert, linhas, chave)
            total += len(registros)
            if espelhar:
                for linha in linhas:
                    id_linha = tuple(linha[i] for i in posicoes_chave)
                    if id_linha in desta_leitura:
                        repetidas += 1
                    desta_leitura.add(id_linha)
            log.info("[%s] página %d: %d registros (acumulado %d)",
                     tabela, pagina, len(registros), total)

        if not espelhar:
            break
        vistos |= desta_leitura
        fechou = _leitura_fechou(len(vistos), total_origem, repetidas)
        if fechou:
            break
        if tentativa < len(tamanhos):
            log.warning(
                "[%s] espelho: a leitura %d trouxe %d ids distintos (%d repetidos) e a origem "
                "declara %s; a paginação pulou registros, relendo com outro tamanho de página",
                tabela, tentativa, len(desta_leitura), repetidas,
                "?" if total_origem is None else total_origem)

    if espelhar:
        total = len(vistos)  # as releituras repetem linhas: conta só os registros distintos
        if fechou:
            _remover_apagados_na_origem(conn, schema, tabela, leitura_anterior, total)
        else:
            # Nada é removido, e a próxima tentativa fica para daqui a CVDW_ESPELHO_HORAS: a
            # marca de leitura completa é gravada mesmo assim, para um objeto que nunca fecha
            # não ser relido (4 vezes) a cada hora. Isso não afrouxa a limpeza, que sempre
            # exige que a leitura DAQUELA execução tenha fechado.
            log.warning(
                "[%s] espelho: nenhuma leitura fechou com o total da origem (%d distintos de "
                "%s); nada foi removido, nova tentativa em %d h",
                tabela, total, "?" if total_origem is None else total_origem,
                cfg_api.espelho_horas)

    # Snapshot do dia: copia o estado atual (todas as colunas exceto a técnica).
    colunas_copia = [n for n, _ in colunas_db if n != COL_TECNICA]
    qtd_snap = db.atualizar_snapshot(conn, schema, tabela, colunas_copia)

    # Marca para o próximo incremental = início desta execução (alta-marca).
    db.registrar_controle(conn, schema, tabela, inicio_execucao, modo, total, "OK", None,
                          leitura_completa=data_extracao if espelhar else None)
    conn.commit()

    log.info("[%s] OK: %d registros ingeridos; snapshot do dia com %d linhas",
             tabela, total, qtd_snap)
    return total


def _espelho_vencido(
    conn: psycopg.Connection,
    cfg_api: ConfigAPI,
    schema: str,
    obj: Objeto,
    modo: str,
    agora: datetime,
) -> bool:
    """Indica se esta execução deve ser a leitura completa de espelho do objeto."""
    if not obj.espelho:
        return False
    if modo == "full" or obj.sempre_full:
        return True  # a leitura já é completa: aproveita para espelhar
    ultima = db.ler_leitura_completa(conn, schema, obj.nome_logico)
    return ultima is None or agora - ultima >= timedelta(hours=cfg_api.espelho_horas)


# Quanto abaixo do tamanho de página configurado ficam as releituras de um espelho que não
# fechou com o total da origem. Cada tamanho desloca as fronteiras entre páginas, que é onde a
# paginação do CVDW repete e pula registros (R32). Com 500 de padrão: 400, 450 e 350.
_RELEITURAS_ABAIXO_DO_PADRAO = (100, 50, 150)
_PAGINA_MINIMA = 50


def _tamanhos_de_leitura(padrao: int) -> list[int | None]:
    """Tamanhos de página de uma leitura de espelho: `None` (o configurado) e as releituras."""
    menores = [padrao - d for d in _RELEITURAS_ABAIXO_DO_PADRAO if padrao - d >= _PAGINA_MINIMA]
    return [None, *menores]


def _leitura_fechou(distintos: int, total_origem: int | None, repetidas: int) -> bool:
    """Diz se as leituras já trouxeram tudo o que a origem declara ter.

    Com o total da origem, basta ter visto tantos ids distintos quanto ele (a união das
    leituras, porque cada uma pula registros diferentes). Sem o total (as definições de
    workflow não o trazem), vale a leitura sem nenhum id repetido: o repetido é o sintoma de
    que a fronteira entre páginas se desencontrou e de que algum registro foi pulado.
    """
    if total_origem is None:
        return repetidas == 0
    return distintos >= total_origem


# Quantas linhas uma limpeza de espelho pode apagar de uma vez, no mínimo, antes de a trava
# de proporção (um quarto da tabela) entrar. Existe para uma leitura que veio incompleta não
# esvaziar a tabela: nesse caso a execução do objeto falha, e a bronze fica como estava.
_REMOCAO_MINIMA_SEGURA = 50


def _remover_apagados_na_origem(
    conn: psycopg.Connection,
    schema: str,
    tabela: str,
    leitura_anterior: datetime | None,
    lidas: int,
) -> int:
    """Apaga da bronze o que a origem deixou de devolver (objetos com `espelho`).

    Toda linha lida leva `_data_extracao` igual ao início da leitura. O que ficou com extração
    anterior à PENÚLTIMA leitura completa não foi devolvido nem nela nem agora, então saiu da
    origem de fato. Só chega aqui uma leitura que fechou com o total da origem (a paginação do
    CVDW pula registros de mesma data de modificação, e sempre os mesmos para o mesmo tamanho
    de página, então a leitura precisa ser conferida: R32). Exigir duas leituras seguidas fica
    como segunda camada, para um registro criado ou apagado no meio da leitura.
    """
    if leitura_anterior is None:
        log.info("[%s] espelho: 1ª leitura completa registrada, ainda não remove nada", tabela)
        return 0
    if lidas == 0:
        log.warning("[%s] espelho: a origem não devolveu nenhum registro, nada será removido",
                    tabela)
        return 0
    candidatas, total = db.contar_nao_vistos(conn, schema, tabela, leitura_anterior)
    if not candidatas:
        return 0
    limite = max(_REMOCAO_MINIMA_SEGURA, total // 4)
    if candidatas > limite:
        raise RuntimeError(
            f"espelho de {schema}.{tabela} abortado: removeria {candidatas} de {total} linhas "
            f"(limite de segurança {limite}). Confira a origem antes de repetir."
        )
    apagadas = db.apagar_nao_vistos(conn, schema, tabela, leitura_anterior)
    log.warning("[%s] espelho: %d linha(s) removida(s) da bronze, a origem não as devolve "
                "mais (continuam nos snapshots dos dias anteriores)", tabela, apagadas)
    return apagadas


def _data_referencia_incremental(
    conn: psycopg.Connection,
    cfg_api: ConfigAPI,
    schema: str,
    obj: Objeto,
    modo: str,
) -> str | None:
    """Calcula o valor de a_partir_data_referencia para o modo incremental."""
    if modo != "incremental":
        return None
    if obj.sempre_full:
        # O `data_referencia` deste objeto não acompanha edição de campo solto
        # (ver config/objetos.yml e R26): qualquer janela deixaria de fora a
        # linha corrigida depois da última movimentação. Lê tudo, sempre.
        return None
    tabela = obj.nome_logico
    ultima = db.ler_data_referencia(conn, schema, tabela)
    if not ultima:
        log.info("[%s] sem marca anterior — fazendo carga completa neste objeto", tabela)
        return None
    # Subtrai a margem de segurança (cobre fuso/atraso; sobreposição é deduplicada).
    inicio = ultima - timedelta(hours=cfg_api.buffer_incremental_horas)
    # A API CVDW só aceita a DATA (YYYY-MM-DD); qualquer formato com hora dá HTTP 400.
    # A granularidade de dia é suficiente — a sobreposição é deduplicada no upsert.
    return inicio.strftime("%Y-%m-%d")


def _avisar_drift(
    tabela: str,
    registro: dict[str, Any],
    colunas_fonte: Sequence[tuple[str, str]],
    tem_dados_brutos: bool,
) -> bool:
    """Avisa (uma vez) se a API trouxe chaves que não existem como coluna."""
    if tem_dados_brutos:
        return True
    conhecidas = {c for c, _ in colunas_fonte}
    novas = {nome_coluna(k) for k in registro.keys()} - conhecidas
    if novas:
        log.warning("[%s] drift de schema: chaves sem coluna serão ignoradas: %s",
                    tabela, ", ".join(sorted(novas)))
    return True


def executar(modo: str, alvo: set[str] | None, criar_tabelas: bool) -> int:
    """Executa a ingestão de todos os objetos selecionados. Retorna o exit code."""
    cfg_api = carregar_config_api()
    cfg_pg = carregar_config_pg()
    objetos = carregar_objetos()
    if alvo:
        objetos = [o for o in objetos if o.nome_logico in alvo]

    cliente = ClienteCVDW(cfg_api)
    schema = cfg_pg.bronze_schema
    inicio_execucao = datetime.now(timezone.utc)
    resultados: list[tuple[str, str, int, str | None]] = []

    with db.conectar(cfg_pg) as conn:
        db.garantir_schema_e_controle(conn, schema)
        if criar_tabelas:
            if not BRONZE_SQL.exists():
                log.error("bronze.sql não encontrado em %s — rode gerar_ddl_bronze.py",
                          BRONZE_SQL)
                return 1
            db.aplicar_ddl(conn, str(BRONZE_SQL))

        log.info("Ingestão modo=%s | %d objeto(s) | schema=%s",
                 modo, len(objetos), schema)

        for obj in objetos:
            try:
                n = ingerir_objeto(conn, cliente, cfg_api, schema, obj, modo,
                                   inicio_execucao)
                resultados.append((obj.nome_logico, "OK", n, None))
            except Exception as exc:  # noqa: BLE001 — isola falhas por objeto
                conn.rollback()  # desfaz o que tiver começado para este objeto
                log.exception("[%s] FALHOU", obj.nome_logico)
                # Registra a falha em transação própria (não some no rollback).
                try:
                    db.registrar_falha_controle(conn, schema, obj.nome_logico, modo,
                                                str(exc))
                except Exception:  # noqa: BLE001
                    log.error("[%s] não foi possível registrar a falha no controle",
                              obj.nome_logico)
                resultados.append((obj.nome_logico, "ERRO", 0, str(exc)))

    return _imprimir_resumo(modo, resultados)


def _imprimir_resumo(
    modo: str, resultados: list[tuple[str, str, int, str | None]]
) -> int:
    """Imprime o resumo final e devolve 1 se houve qualquer falha."""
    ok = [r for r in resultados if r[1] == "OK"]
    erros = [r for r in resultados if r[1] == "ERRO"]
    total_reg = sum(r[2] for r in ok)

    log.info("=" * 64)
    log.info("RESUMO (modo=%s): %d OK (%d registros), %d falha(s)",
             modo, len(ok), total_reg, len(erros))
    for nome, _, n, _msg in ok:
        log.info("  OK   %-32s %d registros", nome, n)
    for nome, _, _n, msg in erros:
        log.error("  ERRO %-32s %s", nome, (msg or "")[:160])
    log.info("=" * 64)
    return 1 if erros else 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ingestão CVDW -> bronze (Postgres).")
    grupo = parser.add_mutually_exclusive_group(required=True)
    grupo.add_argument("--full", action="store_true", help="Carga inicial completa.")
    grupo.add_argument("--incremental", action="store_true",
                       help="Carga incremental (delta desde a última execução).")
    parser.add_argument("--objetos", type=str, default=None,
                        help="Lista separada por vírgula para limitar a ingestão.")
    parser.add_argument("--criar-tabelas", action="store_true",
                        help="Aplica sql/bronze/bronze.sql antes de ingerir.")
    parser.add_argument("--verbose", action="store_true", help="Logs em DEBUG.")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    configurar_logging(args.verbose)
    modo = "full" if args.full else "incremental"
    alvo = {n.strip() for n in args.objetos.split(",")} if args.objetos else None
    return executar(modo, alvo, args.criar_tabelas)


if __name__ == "__main__":
    raise SystemExit(main())
