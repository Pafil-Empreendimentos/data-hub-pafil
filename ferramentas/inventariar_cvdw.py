"""Varredura do catálogo CVDW: lista os endpoints da referência oficial, conta quantos
registros cada um tem ao vivo e aponta quais já são ingeridos. Só leitura (GET).

  python -m ferramentas.inventariar_cvdw [--saida docs/cvcrm-api-inventario.md] [--sem-contagem]

O caminho de cada endpoint vem do índice do portal do desenvolvedor (`llms.txt`) e da
página `.md` de cada referência, nunca de chute: um HTTP 405 num caminho inventado não
prova que o dado não existe (por isso `correspondentes-empresas` tem hífen e não barra).
Com a contagem ligada, a varredura faz uma requisição leve por endpoint, no mesmo ritmo
da ingestão (cerca de 5 minutos para o catálogo todo).
"""
from __future__ import annotations

import argparse
import json
import logging
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import requests

from config.settings import RAIZ, carregar_config_api, carregar_objetos
from cvdw.api import ClienteCVDW, ErroAPI
from cvdw.log import configurar_logging

INDICE_URL = "https://desenvolvedor.cvcrm.com.br/llms.txt"
SECAO = "## Referências das Apis: CVDW"
SAIDA_PADRAO = RAIZ / "docs" / "cvcrm-api-inventario.md"

# Palavras que marcam os endpoints dos dois módulos em foco (comissão e repasse).
_TEMAS = (("comiss", "Comissão"), ("repasse", "Repasse"), ("correspond", "Repasse"))


@dataclass
class Endpoint:
    grupo: str
    titulo: str
    url_doc: str
    path: str = ""
    total: int | None = None
    campos: list[str] = field(default_factory=list)
    situacao: str = ""  # "ok", "vazio", "sem acesso", "erro" ou "" (não contado)
    detalhe: str = ""
    ingerido_como: str = ""

    @property
    def tema(self) -> str:
        for chave, rotulo in _TEMAS:
            if chave in self.path:
                return rotulo
        return ""


def baixar_indice() -> list[Endpoint]:
    """Lê a seção CVDW do llms.txt: linhas '- Grupo' e '  - [Título](url.md)'."""
    texto = requests.get(INDICE_URL, timeout=60).text
    linhas = texto.splitlines()
    inicio = next(i for i, l in enumerate(linhas) if l.strip() == SECAO)
    endpoints: list[Endpoint] = []
    grupo = ""
    for linha in linhas[inicio + 1:]:
        if linha.startswith("## "):
            break
        if linha.startswith("- "):
            grupo = linha[2:].strip()
            continue
        achou = re.match(r"\s+- \[(.+?)\]\((https://\S+?\.md)\)", linha)
        if achou:
            endpoints.append(Endpoint(grupo, achou.group(1).strip(), achou.group(2)))
    return endpoints


def descobrir_path(ep: Endpoint) -> None:
    """Abre a página .md da referência e lê o caminho real no bloco OpenAPI."""
    corpo = requests.get(ep.url_doc, timeout=60).text
    bloco = re.search(r"```json\s*(\{.*?\})\s*```", corpo, re.S)
    if not bloco:
        ep.situacao, ep.detalhe = "erro", "página sem bloco OpenAPI"
        return
    caminhos = json.loads(bloco.group(1)).get("paths", {})
    if caminhos:
        ep.path = next(iter(caminhos)).strip("/")


def contar(ep: Endpoint, cliente: ClienteCVDW) -> None:
    """Uma requisição leve por endpoint: total na origem e nomes dos campos."""
    try:
        ep.total, ep.campos = cliente.sondar(ep.path)
        ep.situacao = "ok" if ep.total else "vazio"
    except ErroAPI as exc:
        msg = str(exc)
        ep.situacao = "sem acesso" if "HTTP 403" in msg or "(autenticação)" in msg else "erro"
        ep.detalhe = re.sub(r"\s+", " ", msg)[:90]


def _md_tabela(titulo: str, eps: list[Endpoint]) -> list[str]:
    saida = [f"### {titulo}", "",
             "| Endpoint | O que devolve | Registros | Campos | Ingestão |",
             "|---|---|---:|---:|---|"]
    for ep in eps:
        if ep.situacao == "ok":
            registros = f"{ep.total:,}".replace(",", ".")
        elif ep.situacao == "vazio":
            registros = "0"
        elif ep.situacao in ("erro", "sem acesso"):
            registros = ep.situacao
        else:
            registros = "n/c"
        campos = str(len(ep.campos)) if ep.campos else "-"
        ingestao = f"`{ep.ingerido_como}`" if ep.ingerido_como else "não"
        saida.append(f"| `{ep.path}` | {ep.titulo} | {registros} | {campos} | {ingestao} |")
    return saida + [""]


def gerar_markdown(eps: list[Endpoint], contado: bool) -> str:
    total_ing = sum(1 for e in eps if e.ingerido_como)
    com_dados = sum(1 for e in eps if e.situacao == "ok")
    vazios = sum(1 for e in eps if e.situacao == "vazio")
    problemas = sum(1 for e in eps if e.situacao in ("erro", "sem acesso"))
    linhas = [
        "# Inventário da API CVDW do CVCRM",
        "",
        f"Gerado em {datetime.now():%d/%m/%Y %H:%M} por `python -m ferramentas.inventariar_cvdw`.",
        f"Fonte: índice do portal do desenvolvedor ({INDICE_URL}) e a página de cada referência.",
        "Todas as chamadas são GET e a contagem é a que a própria API reporta no envelope",
        "(`total_de_registros`). Para atualizar este arquivo, rode a ferramenta de novo.",
        "",
        "## Resumo",
        "",
        f"- Endpoints no catálogo CVDW: **{len(eps)}**.",
        f"- Já ingeridos na bronze (`config/objetos.yml`): **{total_ing}**.",
    ]
    if contado:
        linhas += [f"- Com registros: **{com_dados}**. Vazios: **{vazios}**. "
                   f"Com erro ou sem permissão: **{problemas}**."]
    linhas += ["", "A coluna Ingestão mostra o nome lógico do objeto na bronze, ou `não`.", ""]

    foco = [e for e in eps if e.tema]
    if foco:
        linhas += ["## Comissão e Repasse (foco desta análise)", ""]
        linhas += _md_tabela("Endpoints dos dois módulos", foco)
        linhas += ["### Campos que cada um devolve", ""]
        for ep in foco:
            if ep.campos:
                linhas += [f"**`{ep.path}`** ({len(ep.campos)} campos)", "",
                           "```", ", ".join(ep.campos), "```", ""]

    linhas += ["## Catálogo completo, por grupo", ""]
    grupos: dict[str, list[Endpoint]] = {}
    for ep in eps:
        grupos.setdefault(ep.grupo, []).append(ep)
    for nome, lista in grupos.items():
        linhas += _md_tabela(nome, lista)

    problemas_lista = [e for e in eps if e.situacao in ("erro", "sem acesso")]
    if problemas_lista:
        linhas += ["## Endpoints que não responderam", ""]
        for e in problemas_lista:
            nota = ""
            if re.match(r"v\d+/", e.path):
                nota = (" A referência mistura o servidor /api/v1/cvdw com um caminho /vN/...: "
                        "o endpoint equivalente costuma estar na lista acima, sem o prefixo.")
            linhas.append(f"- `{e.path}`: {e.situacao}. {e.detalhe}{nota}")
        linhas.append("")
    return "\n".join(linhas)


def main() -> int:
    parser = argparse.ArgumentParser(description="Inventário do catálogo CVDW (só leitura).")
    parser.add_argument("--saida", type=Path, default=SAIDA_PADRAO,
                        help="Arquivo markdown de saída.")
    parser.add_argument("--sem-contagem", action="store_true",
                        help="Só lê o índice e os caminhos; não chama a API de dados.")
    args = parser.parse_args()

    configurar_logging(False)
    logging.getLogger("cvdw.api").setLevel(logging.WARNING)

    eps = baixar_indice()
    print(f"{len(eps)} endpoints no catálogo CVDW. Descobrindo caminhos...", flush=True)
    for ep in eps:
        descobrir_path(ep)
        time.sleep(0.15)  # gentileza com o portal de documentação

    # Só os objetos do próprio CVDW: as definições de workflow vivem em outro grupo da API.
    ingeridos = {o.path.strip("/"): o.nome_logico for o in carregar_objetos()
                 if o.base == "cvdw"}
    for ep in eps:
        ep.ingerido_como = ingeridos.get(ep.path, "")

    contado = not args.sem_contagem
    if contado:
        cliente = ClienteCVDW(carregar_config_api())
        for n, ep in enumerate(eps, 1):
            if not ep.path:
                continue
            contar(ep, cliente)
            marca = f"{ep.total}" if ep.situacao in ("ok", "vazio") else ep.situacao
            print(f"[{n:>3}/{len(eps)}] {ep.path:<45} {marca}", flush=True)

    args.saida.write_text(gerar_markdown(eps, contado), encoding="utf-8")
    print(f"\nInventário gravado em {args.saida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
