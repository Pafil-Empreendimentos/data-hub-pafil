# Ferramentas do analista

Scripts de uso manual. Nada aqui é agendado nem faz parte da carga diária: servem para
conferir números, regerar documentos e abrir uma consulta no banco. Rode sempre da raiz
do repositório, como módulo:

```bash
python -m ferramentas.<nome> [opções]
```

| Ferramenta | Para que serve |
|---|---|
| `inventariar_cvdw` | Lista todos os endpoints do catálogo CVDW (índice oficial do portal do desenvolvedor), conta os registros de cada um ao vivo e aponta quais já são ingeridos. Só leitura, leva cerca de 5 minutos. Gera [`docs/cvcrm-api-inventario.md`](../docs/cvcrm-api-inventario.md) |
| `conferir_mdnet` | Compara a telefonia carregada (bronze, silver e gold) com os totais do painel da MDnet. Só leitura |
| `reconciliar_vendas` | Compara as vendas da plataforma com a planilha legada `Vendas Consolidadas.xlsm`, proposta a proposta. Gera o relatório em `reconciliacao/` |
| `reconciliar_distratos` | Compara os distratos da plataforma com o CSV legado `rel_distratos`, de um mês. Gera o relatório em `reconciliacao/` |
| `gerar_depara_classificacao` | Gera o `de_para_classificacao.xlsx` (classificação oficial por proposta) a partir da Vendas Consolidadas |
| `gerar_doc_deparas` | Gera uma planilha de documentação dos de-paras a partir de `config/deparas.yml` |
| `montar_estrutura_depara` | Materializa, na pasta de de-paras do SharePoint/OneDrive, a estrutura versionada que o Power BI lê |
| `consultar.ps1` | Abre o `psql` no banco apontado pelo `.env`: `.\ferramentas\consultar.ps1 -c "SELECT 1"` |

As reconciliações foram a prova de que a plataforma reproduz o fechamento manual
(veja [`reconciliacao/`](../reconciliacao/)). Elas precisam dos arquivos legados, que não
estão no repositório.
