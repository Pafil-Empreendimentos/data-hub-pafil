"""Conferência da bronze.mdnet_cdr contra os totais do painel da MDnet. Só leitura.

  python -m ferramentas.conferir_mdnet [--de 2026-09-01] [--ate 2026-10-01]

Imprime a cobertura da tabela, o total por mês e, para o período pedido, a divisão
por direção e estado, que é a mesma que o painel mostra nos cartões do relatório de
chamadas. Serve para provar que a carga está fiel antes de modelar a silver.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime, timedelta
from typing import Any, Sequence

from config.settings import carregar_config_pg
from cvdw import db

TABELA = "mdnet_cdr"


def _data(texto: str) -> date:
    try:
        return date.fromisoformat(texto)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{texto!r} não é uma data AAAA-MM-DD") from exc


def _tabela(titulo: str, cabecalho: Sequence[str], linhas: Sequence[Sequence[Any]]) -> None:
    print(f"\n{titulo}")
    textos = [[str(c) for c in linha] for linha in linhas]
    larguras = [max(len(h), *(len(t[i]) for t in textos)) if textos else len(h)
                for i, h in enumerate(cabecalho)]
    print("  " + "  ".join(h.ljust(larguras[i]) for i, h in enumerate(cabecalho)))
    print("  " + "  ".join("-" * w for w in larguras))
    for t in textos:
        print("  " + "  ".join(c.ljust(larguras[i]) for i, c in enumerate(t)))


def main() -> int:
    parser = argparse.ArgumentParser(description="Confere bronze.mdnet_cdr com o painel.")
    parser.add_argument("--de", type=_data, default=date(2026, 9, 1), metavar="AAAA-MM-DD")
    parser.add_argument("--ate", type=_data, default=date(2026, 10, 1), metavar="AAAA-MM-DD")
    parser.add_argument("--silver", action="store_true",
                        help="Confere também a view silver.mdnet_chamadas (direção corrigida).")
    parser.add_argument("--detalhe", action="store_true",
                        help="Mostra cortes extras para investigar divergência de classificação.")
    parser.add_argument("--ura", action="store_true",
                        help="Confere o relatório de URA (bronze.mdnet_ura e as views silver da URA).")
    parser.add_argument("--gold", action="store_true",
                        help="Confere gold.fato_chamadas e gold.dim_ramal (a base da página Telefonia).")
    args = parser.parse_args()

    cfg = carregar_config_pg()
    tab = f"{cfg.bronze_schema}.{TABELA}"
    inicio = datetime.combine(args.de, datetime.min.time())
    fim = datetime.combine(args.ate + timedelta(days=1), datetime.min.time())

    with db.conectar(cfg) as conn:
        menor, maior, total = conn.execute(
            f"SELECT min(data_hora_inicio), max(data_hora_inicio), count(*) FROM {tab}"
        ).fetchone()
        print(f"Tabela {tab}: {total} linha(s), de {menor} a {maior}")

        _tabela(
            "Total por mês",
            ("mês", "chamadas"),
            conn.execute(
                f"SELECT to_char(date_trunc('month', data_hora_inicio), 'YYYY-MM'), count(*) "
                f"FROM {tab} GROUP BY 1 ORDER BY 1"
            ).fetchall(),
        )

        linhas = conn.execute(
            f"SELECT coalesce(direcao, '(vazio)'), coalesce(estado, '(vazio)'), count(*) "
            f"FROM {tab} WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            f"GROUP BY 1, 2 ORDER BY 1, 2",
            (inicio, fim),
        ).fetchall()
        _tabela(f"Direção x estado, de {args.de} a {args.ate}",
                ("direção", "estado", "chamadas"), linhas)
        print(f"\n  Total do período: {sum(l[2] for l in linhas)}")

        (distintos,) = conn.execute(
            f"SELECT count(DISTINCT origem) FROM {tab} "
            f"WHERE direcao = 'Entrada' AND data_hora_inicio >= %s AND data_hora_inicio < %s",
            (inicio, fim),
        ).fetchone()
        print(f"  Origens distintas em Entrada: {distintos} "
              f"(o painel chama de 'capilaridade da entrada' um número perto disso)")

        (repetidos,) = conn.execute(
            f"SELECT count(*) FROM (SELECT protocolo FROM {tab} "
            f"GROUP BY protocolo HAVING count(*) > 1) t"
        ).fetchone()
        print(f"  Protocolos que aparecem em mais de uma linha: {repetidos}")

        if args.detalhe:
            _detalhe(conn, tab, inicio, fim)
        if args.silver:
            _silver(conn, inicio, fim)
        if args.ura:
            _ura(conn, args.de, args.ate)
        if args.gold:
            _gold(conn, args.de, args.ate)
    return 0


def _detalhe(conn: Any, tab: str, inicio: datetime, fim: datetime) -> None:
    """Cortes para descobrir por que a classificação do painel difere da coluna Direção.

    Nenhuma linha mostra telefone: origem e destino entram só como 'ramal' (até 5
    dígitos) ou 'externo'.
    """
    periodo = (inicio, fim)

    _tabela(
        "Direção x tipo x estado",
        ("direção", "tipo", "estado", "chamadas"),
        conn.execute(
            f"SELECT coalesce(direcao, '(vazio)'), coalesce(tipo, '(vazio)'), "
            f"coalesce(estado, '(vazio)'), count(*) FROM {tab} "
            f"WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            f"GROUP BY 1, 2, 3 ORDER BY 1, 2, 3",
            periodo,
        ).fetchall(),
    )

    _tabela(
        "Direção x origem x destino x estado (ramal = até 5 dígitos)",
        ("direção", "origem", "destino", "estado", "chamadas"),
        conn.execute(
            f"SELECT coalesce(direcao, '(vazio)'), "
            f"CASE WHEN length(coalesce(origem, '')) <= 5 THEN 'ramal' ELSE 'externo' END, "
            f"CASE WHEN length(coalesce(destino, '')) <= 5 THEN 'ramal' ELSE 'externo' END, "
            f"coalesce(estado, '(vazio)'), count(*) FROM {tab} "
            f"WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            f"GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4",
            periodo,
        ).fetchall(),
    )

    _tabela(
        "Direção x estado x conversa x ramal x transferência",
        ("direção", "estado", "conversa", "ramal", "transferência", "chamadas"),
        conn.execute(
            f"SELECT coalesce(direcao, '(vazio)'), coalesce(estado, '(vazio)'), "
            f"CASE WHEN coalesce(tempo_falado, '00:00:00') = '00:00:00' "
            f"THEN 'sem conversa' ELSE 'com conversa' END, "
            f"CASE WHEN coalesce(ramal, '') = '' THEN 'sem ramal' ELSE 'com ramal' END, "
            f"CASE WHEN coalesce(tipo_transferencia, '') = '' "
            f"THEN 'sem transf.' ELSE 'transferida' END, count(*) FROM {tab} "
            f"WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            f"GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 2, 3, 4, 5",
            periodo,
        ).fetchall(),
    )

    _tabela(
        "Protocolos repetidos (toda a tabela)",
        ("protocolo", "linhas", "direção e início de cada uma"),
        conn.execute(
            f"SELECT protocolo, count(*), "
            f"string_agg(coalesce(direcao, '?') || ' ' || "
            f"to_char(data_hora_inicio, 'DD/MM HH24:MI:SS'), ' | ' ORDER BY data_hora_inicio) "
            f"FROM {tab} GROUP BY protocolo HAVING count(*) > 1 "
            f"ORDER BY 2 DESC, 1 LIMIT 20"
        ).fetchall(),
    )

    _tabela(
        "Linhas com protocolo sintético (SEM-...), por mês",
        ("mês", "linhas"),
        conn.execute(
            f"SELECT to_char(date_trunc('month', data_hora_inicio), 'YYYY-MM'), count(*) "
            f"FROM {tab} WHERE protocolo LIKE 'SEM-%%' GROUP BY 1 ORDER BY 1"
        ).fetchall(),
    )




def _silver(conn: Any, inicio: datetime, fim: datetime) -> None:
    """Resumo da silver.mdnet_chamadas, na mesma forma dos cartões do painel web."""
    periodo = (inicio, fim)
    (total,) = conn.execute(
        "SELECT count(*) FROM silver.mdnet_chamadas "
        "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s", periodo,
    ).fetchone()
    print()
    print(f"silver.mdnet_chamadas no período: {total} linha(s)")

    _tabela(
        "Direção da silver x estado do painel (compare com os cartões do painel web)",
        ("direção", "estado", "chamadas"),
        conn.execute(
            "SELECT direcao, coalesce(estado_painel, '(vazio)'), count(*) "
            "FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            "GROUP BY 1, 2 ORDER BY 1, 2", periodo,
        ).fetchall(),
    )

    _tabela(
        "Direção do CARTÃO da silver x estado do cartão (compare com o painel web)",
        ("direção", "estado", "chamadas"),
        conn.execute(
            "SELECT direcao_cartao, coalesce(estado_cartao, '(vazio)'), count(*) "
            "FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            "GROUP BY 1, 2 ORDER BY 1, 2", periodo,
        ).fetchall(),
    )

    _tabela(
        "Tipos de perna por ligação (0 = nenhuma perna carregada, deveria ser raro)",
        ("tipos de perna", "ligações"),
        conn.execute(
            "SELECT tem_perna_entrada::int + tem_perna_saida::int + tem_perna_interna::int, "
            "count(*) FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s GROUP BY 1 ORDER BY 1",
            periodo,
        ).fetchall(),
    )

    _tabela(
        "Marcas da silver",
        ("marca", "linhas"),
        conn.execute(
            "SELECT 'e_recurso', count(*) FILTER (WHERE e_recurso) "
            "FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            "UNION ALL SELECT 'e_perna_de_transferencia', "
            "count(*) FILTER (WHERE e_perna_de_transferencia) FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            "UNION ALL SELECT 'e_perna_de_tronco', count(*) FILTER (WHERE e_perna_de_tronco) "
            "FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s "
            "UNION ALL SELECT 'e_chamada_real', count(*) FILTER (WHERE e_chamada_real) "
            "FROM silver.mdnet_chamadas "
            "WHERE data_hora_inicio >= %s AND data_hora_inicio < %s",
            periodo * 4,
        ).fetchall(),
    )

    _tabela(
        "Entrada real por mês",
        ("mês", "entradas", "atendidas", "% atendida"),
        conn.execute(
            "SELECT to_char(date_trunc('month', data_hora_inicio), 'YYYY-MM'), count(*), "
            "count(*) FILTER (WHERE atendida), "
            "round(100.0 * count(*) FILTER (WHERE atendida) / count(*), 1) "
            "FROM silver.mdnet_chamadas "
            "WHERE e_chamada_real AND direcao = 'Entrada' "
            "AND data_hora_inicio >= %s AND data_hora_inicio < %s "
            "GROUP BY 1 ORDER BY 1", periodo,
        ).fetchall(),
    )

    _tabela(
        "Quem atendeu as entradas, por setor e responsável (silver.dpara_ramais)",
        ("setor", "responsável", "atendidas"),
        conn.execute(
            "SELECT coalesce(setor_ramal, '(ramal fora da planilha)'), "
            "coalesce(responsavel_ramal, ''), count(*) "
            "FROM silver.mdnet_chamadas "
            "WHERE e_chamada_real AND direcao = 'Entrada' AND atendida AND ramal IS NOT NULL "
            "AND data_hora_inicio >= %s AND data_hora_inicio < %s "
            "GROUP BY 1, 2 ORDER BY 3 DESC, 1 LIMIT 25", periodo,
        ).fetchall(),
    )

    _tabela(
        "Ramais que atenderam entrada e NÃO estão na planilha de ramais (acrescente lá)",
        ("ramal", "atendidas"),
        conn.execute(
            "SELECT ramal, count(*) FROM silver.mdnet_chamadas "
            "WHERE e_chamada_real AND direcao = 'Entrada' AND atendida AND ramal IS NOT NULL "
            "AND setor_ramal IS NULL "
            "AND data_hora_inicio >= %s AND data_hora_inicio < %s "
            "GROUP BY 1 ORDER BY 2 DESC LIMIT 15", periodo,
        ).fetchall(),
    )


def _ura(conn: Any, de: date, ate: date) -> None:
    """Confere o relatório de URA: contagens no formato dos gráficos da tela, e o funil.

    Os totais por menu e por opção devem ser IGUAIS aos gráficos "Quantidade de chamadas por
    URA" e "Quantidades de Chamadas por Opção da URA" da tela do painel, no mesmo período.
    """
    periodo = (de, ate)
    (total,) = conn.execute(
        "SELECT count(*) FROM bronze.mdnet_ura WHERE data >= %s AND data <= %s", periodo,
    ).fetchone()
    print()
    print(f"bronze.mdnet_ura de {de} a {ate}: {total} passagem(ns)")

    _tabela(
        "Chamadas por URA (compare com o gráfico 'Quantidade de chamadas por URA')",
        ("URA", "passagens"),
        conn.execute(
            "SELECT ura, count(*) FROM bronze.mdnet_ura WHERE data >= %s AND data <= %s "
            "GROUP BY 1 ORDER BY 2 DESC", periodo,
        ).fetchall(),
    )

    # O painel escreve o rótulo em maiúsculas; o maiúsculo do Postgres com locale C não trata
    # acento, então a conversão fica para o Python.
    linhas = conn.execute(
        "SELECT ura, opcao, count(*) FROM silver.mdnet_ura_passagens "
        "WHERE data >= %s AND data <= %s GROUP BY 1, 2 ORDER BY 1, 3 DESC", periodo,
    ).fetchall()
    _tabela(
        "Chamadas por opção (compare com o gráfico 'Quantidades de Chamadas por Opção da URA')",
        ("rótulo", "chamadas"),
        [(f"{ura} - {opcao}".upper(), n) for ura, opcao, n in linhas],
    )

    _tabela(
        "Funil pelo menu atual (código e nome da locução) e o que aconteceu depois no CDR",
        ("opção", "chamadas", "atendidas", "% atend.", "espera média (s)"),
        conn.execute(
            "SELECT coalesce(codigo_opcao || ' ', '') || caminho_nome, count(*), "
            "count(*) FILTER (WHERE atendida), "
            "round(100.0 * count(*) FILTER (WHERE atendida) / count(*), 0), "
            "round(avg(espera_s) FILTER (WHERE atendida)) "
            "FROM silver.mdnet_ura_chamadas WHERE data >= %s AND data <= %s AND e_menu_atual "
            "GROUP BY 1 ORDER BY 2 DESC", periodo,
        ).fetchall(),
    )

    _tabela(
        "Cada opção do menu e o setor que atendeu (silver.dpara_ramais)",
        ("opção", "setor que atendeu", "atendidas"),
        conn.execute(
            "SELECT coalesce(codigo_opcao || ' ', '') || nome_opcao, "
            "coalesce(setor_atendente, '(ramal fora da planilha ou não ramal)'), count(*) "
            "FROM silver.mdnet_ura_chamadas "
            "WHERE data >= %s AND data <= %s AND e_menu_atual AND atendida "
            "GROUP BY 1, 2 ORDER BY 1, 3 DESC", periodo,
        ).fetchall(),
    )

    _tabela(
        "Legado: caminhos que o menu atual não explica (e_menu_atual = falso)",
        ("caminho", "chamadas"),
        conn.execute(
            "SELECT caminho, count(*) FROM silver.mdnet_ura_chamadas "
            "WHERE data >= %s AND data <= %s AND NOT e_menu_atual GROUP BY 1 ORDER BY 2 DESC", periodo,
        ).fetchall(),
    )

    _tabela(
        "Por mês: chamadas na URA e o que aconteceu com elas",
        ("mês", "chamadas", "não digitou", "desligou na URA", "atendidas", "% atend."),
        conn.execute(
            "SELECT to_char(date_trunc('month', data), 'YYYY-MM'), count(*), "
            "count(*) FILTER (WHERE escolha_principal = 'Não Digitou'), "
            "count(*) FILTER (WHERE escolha_principal = 'Desligou na URA'), "
            "count(*) FILTER (WHERE atendida), "
            "round(100.0 * count(*) FILTER (WHERE atendida) / count(*), 0) "
            "FROM silver.mdnet_ura_chamadas WHERE data >= %s AND data <= %s "
            "GROUP BY 1 ORDER BY 1", periodo,
        ).fetchall(),
    )

    (casadas, principais) = conn.execute(
        "SELECT count(*) FILTER (WHERE tem_cdr), count(*) FROM silver.mdnet_ura_chamadas "
        "WHERE data >= %s AND data <= %s", periodo,
    ).fetchone()
    print(f"\n  Ligações da URA achadas no CDR: {casadas} de {principais} "
          f"(em set/2026 devem ser 1.012 de 1.012, contando o número oculto)")


def _gold(conn: Any, de: date, ate: date) -> None:
    """Confere a gold da telefonia: a fato fecha com a silver, a dimensão não deixa ramal órfão,
    e o ruído marca só ligação não atendida."""
    periodo = (de, ate)
    (fato, silver, ids, nulos) = conn.execute(
        "SELECT (SELECT count(*) FROM gold.fato_chamadas), "
        "(SELECT count(*) FROM silver.mdnet_chamadas WHERE e_chamada_real), "
        "(SELECT count(DISTINCT chamada_id) FROM gold.fato_chamadas), "
        "(SELECT count(*) FROM gold.fato_chamadas WHERE e_ruido IS NULL)"
    ).fetchone()
    print()
    print(f"gold.fato_chamadas: {fato} linha(s) | silver com e_chamada_real: {silver} | "
          f"chamada_id únicos: {ids} | e_ruido nulo: {nulos}")
    print("  (a fato deve ter o mesmo número de linhas da silver real, ids únicos = linhas, e_ruido nulo = 0)")

    (orfaos, ramais, fora) = conn.execute(
        "SELECT (SELECT count(*) FROM gold.fato_chamadas f LEFT JOIN gold.dim_ramal d USING (ramal) "
        "WHERE f.ramal IS NOT NULL AND d.ramal IS NULL), "
        "(SELECT count(*) FROM gold.dim_ramal), "
        "(SELECT count(*) FROM gold.dim_ramal WHERE NOT cadastrado_na_planilha)"
    ).fetchone()
    print(f"gold.dim_ramal: {ramais} ramal(is), {fora} fora da planilha | ramais da fato sem linha na "
          f"dimensão (deve ser 0): {orfaos}")

    # As duas views (silver e gold) são pesadas: ler cada uma UMA vez, para tabelas temporárias.
    conn.execute(
        "CREATE TEMP TABLE _cartao AS SELECT direcao_cartao, estado_cartao, origem "
        "FROM silver.mdnet_chamadas WHERE data_hora_inicio::date BETWEEN %s AND %s", periodo,
    )
    conn.execute(
        "CREATE TEMP TABLE _fato AS SELECT direcao, atendida "
        "FROM gold.fato_chamadas WHERE data BETWEEN %s AND %s", periodo,
    )

    def _linha_cartao(rotulo: str, direcao: str, obs: str) -> tuple:
        t, a, n = conn.execute(
            "SELECT count(*), count(*) FILTER (WHERE estado_cartao = 'Atendida'), "
            "count(*) FILTER (WHERE estado_cartao <> 'Atendida') FROM _cartao WHERE direcao_cartao = %s",
            (direcao,),
        ).fetchone()
        return (rotulo, t, a, n, obs)

    def _linha_fato(rotulo: str, direcao: str, obs: str) -> tuple:
        t, a, n = conn.execute(
            "SELECT count(*), count(*) FILTER (WHERE atendida), count(*) FILTER (WHERE NOT atendida) "
            "FROM _fato WHERE direcao = %s", (direcao,),
        ).fetchone()
        return (rotulo, t, a, n, obs)

    (total_linhas,) = conn.execute("SELECT count(*) FROM _cartao").fetchone()
    (capilaridade,) = conn.execute(
        "SELECT count(DISTINCT origem) FROM _cartao WHERE direcao_cartao = 'Entrada'"
    ).fetchone()
    _tabela(
        "Cartões do painel web x gold (digite no painel o MESMO período e compare, de preferência logo "
        "depois de uma carga)",
        ("cartão do painel", "total", "atendidas", "não atendidas", "observação"),
        [
            ("Chamadas totais", total_linhas, "", "", "todas as linhas, inclui recurso e perna de transferência"),
            _linha_cartao("Entrada (regra do painel)", "Entrada", "é o cartão TOTAL ENTRADA"),
            _linha_fato("Entrada (fato da gold)", "Entrada", "tem que ser igual à linha de cima"),
            ("Capilaridade da entrada (origens)", capilaridade, "", "",
             "a gold conta cerca de 1 por cento a menos (agrupa variantes do mesmo número)"),
            _linha_cartao("Saída (regra do painel)", "Saída", "atendidas NÃO fecham com o painel (512 x 251)"),
            _linha_fato("Saída (fato da gold)", "Saída", "a fato tira o que não é ligação real"),
            _linha_cartao("Interna (regra do painel)", "Interna", "inclui recurso do PABX e perna de transferência"),
            _linha_fato("Interna (fato da gold)", "Interna", "só interna real, sem recurso nem transferência"),
        ],
    )

    _tabela(
        "Entrada por mês: bruta e sem ruído (a bruta fecha com o painel web)",
        ("mês", "entradas", "atendidas", "% bruto", "ruído", "% sem ruído"),
        conn.execute(
            "SELECT to_char(date_trunc('month', data_hora_inicio), 'YYYY-MM'), count(*), "
            "count(*) FILTER (WHERE atendida), "
            "round(100.0 * count(*) FILTER (WHERE atendida) / count(*), 1), "
            "count(*) FILTER (WHERE e_ruido), "
            "round(100.0 * count(*) FILTER (WHERE atendida) "
            "/ nullif(count(*) FILTER (WHERE NOT e_ruido), 0), 1) "
            "FROM gold.fato_chamadas WHERE direcao = 'Entrada' AND data >= %s AND data <= %s "
            "GROUP BY 1 ORDER BY 1", periodo,
        ).fetchall(),
    )

    _tabela(
        "Ruído por motivo (nenhuma atendida pode estar aqui)",
        ("motivo", "ligações", "atendidas"),
        conn.execute(
            "SELECT coalesce(motivo_ruido, '(não é ruído)'), count(*), count(*) FILTER (WHERE atendida) "
            "FROM gold.fato_chamadas WHERE direcao = 'Entrada' AND data >= %s AND data <= %s "
            "GROUP BY 1 ORDER BY 2 DESC", periodo,
        ).fetchall(),
    )

    _tabela(
        "Entradas atendidas por unidade e setor (janeiro/2026 quase não tem ramal, use --de 2026-02-01)",
        ("unidade", "setor", "atendidas"),
        conn.execute(
            "SELECT coalesce(d.unidade, '(sem ramal)'), coalesce(d.setor_grupo, '(sem ramal)'), count(*) "
            "FROM gold.fato_chamadas f LEFT JOIN gold.dim_ramal d USING (ramal) "
            "WHERE f.direcao = 'Entrada' AND f.atendida AND f.data >= %s AND f.data <= %s "
            "GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20", periodo,
        ).fetchall(),
    )

    _tabela(
        "Atendidas sem ramal, por mês (janeiro/2026 chega a 92%; de fevereiro em diante deve ser baixo)",
        ("mês", "atendidas", "sem ramal", "% sem ramal"),
        conn.execute(
            "SELECT to_char(date_trunc('month', data), 'YYYY-MM'), count(*), "
            "count(*) FILTER (WHERE ramal IS NULL), "
            "round(100.0 * count(*) FILTER (WHERE ramal IS NULL) / count(*), 0) "
            "FROM gold.fato_chamadas WHERE direcao = 'Entrada' AND atendida "
            "AND data >= %s AND data <= %s GROUP BY 1 ORDER BY 1", periodo,
        ).fetchall(),
    )


if __name__ == "__main__":
    raise SystemExit(main())
