"""Aplica gold.sql (star schema) sobre a silver e valida. Requer a silver aplicada.

  python aplicar_gold.py [--validar]
"""
from __future__ import annotations

import argparse

from config.settings import RAIZ, carregar_config_pg
from cvdw import db
from cvdw.log import configurar_logging, get_logger

log = get_logger("aplicar_gold")

GOLD_SQL = RAIZ / "sql" / "gold" / "gold.sql"
# Aplicado depois do gold.sql, e não junto: fato_atendimentos junta com
# gold.dim_empreendimento, que nasce lá.
BLIP_SQL = RAIZ / "sql" / "gold" / "blip.sql"
# Telefonia da MDnet. Depende só da silver (mdnet_chamadas, mdnet_ura_chamadas, dpara_ramais),
# então pode ser reaplicado sozinho com --so-mdnet, sem refazer o resto da gold.
MDNET_SQL = RAIZ / "sql" / "gold" / "mdnet.sql"
# Comissão e repasse. Depende da silver.comissoes_repasses, de silver.reservas e dos de-paras e
# de gold.dim_empreendimento (que nasce em gold.sql), por isso vem depois dele. Pode ser reaplicado
# sozinho com --so-comissoes-repasses.
COMISSOES_REPASSES_SQL = RAIZ / "sql" / "gold" / "comissoes_repasses.sql"

OBJETOS_COMISSOES_REPASSES = [
    "dim_repasse_etapa", "dim_correspondente", "fato_repasses",
    "fato_repasses_etapas", "fato_repasses_movimentos",
    "dim_comissao_situacao", "dim_imobiliaria", "fato_comissoes",
    "fato_comissoes_pagamentos", "fato_comissoes_programacao", "fato_comissoes_regras",
]
OBJETOS = [
    "dim_calendario", "dim_empreendimento", "dim_unidade",
    "dim_corretor", "dim_corretor_headcount", "fato_reservas",
    "fato_leads", "fato_precadastros",
    "dim_fila", "dim_atendente", "fato_atendimentos",
    "fato_atendimentos_cvcrm",
    "dim_ramal", "fato_chamadas",
] + OBJETOS_COMISSOES_REPASSES
OBJETOS_MDNET = ["dim_ramal", "fato_chamadas"]


def validar(conn, objetos=OBJETOS) -> int:
    falhas = 0
    with conn.cursor() as cur:
        for o in objetos:
            try:
                cur.execute(f"SELECT count(*) FROM gold.{o}")
                log.info("  gold.%-28s OK  (%s linhas)", o, cur.fetchone()[0])
            except Exception as exc:  # noqa: BLE001
                conn.rollback()
                log.error("  gold.%-28s FALHOU: %s", o, str(exc).splitlines()[0])
                falhas += 1
    return falhas


def main() -> int:
    ap = argparse.ArgumentParser(description="Aplica a camada gold sobre a silver.")
    ap.add_argument("--validar", action="store_true", help="só valida (não aplica DDL)")
    ap.add_argument("--so-mdnet", action="store_true",
                    help="aplica e valida só a telefonia da MDnet (gold/mdnet.sql)")
    ap.add_argument("--so-comissoes-repasses", action="store_true",
                    help="aplica e valida só comissão e repasse (gold/comissoes_repasses.sql)")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    configurar_logging(args.verbose)
    cfg = carregar_config_pg()

    with db.conectar(cfg) as conn:
        if args.so_comissoes_repasses:
            if not args.validar:
                db.aplicar_ddl(conn, str(COMISSOES_REPASSES_SQL))
                log.info("Views gold de comissão e repasse aplicadas (%s).",
                         COMISSOES_REPASSES_SQL.name)
            log.info("Validação smoke:")
            falhas = validar(conn, OBJETOS_COMISSOES_REPASSES)
            return 1 if falhas else 0

        if args.so_mdnet:
            if not args.validar:
                db.aplicar_ddl(conn, str(MDNET_SQL))
                log.info("Views gold da MDnet aplicadas (%s).", MDNET_SQL.name)
            log.info("Validação smoke:")
            falhas = validar(conn, OBJETOS_MDNET)
            return 1 if falhas else 0

        if not args.validar:
            db.aplicar_ddl(conn, str(GOLD_SQL))
            log.info("Views gold aplicadas (%s).", GOLD_SQL.name)
            db.aplicar_ddl(conn, str(BLIP_SQL))
            log.info("Views gold do Blip aplicadas (%s).", BLIP_SQL.name)
            db.aplicar_ddl(conn, str(MDNET_SQL))
            log.info("Views gold da MDnet aplicadas (%s).", MDNET_SQL.name)
            db.aplicar_ddl(conn, str(COMISSOES_REPASSES_SQL))
            log.info("Views gold de comissão e repasse aplicadas (%s).",
                     COMISSOES_REPASSES_SQL.name)
        log.info("Validação smoke:")
        falhas = validar(conn)

    if falhas:
        log.error("%d objeto(s) gold com erro.", falhas)
        return 1
    log.info("Gold OK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
