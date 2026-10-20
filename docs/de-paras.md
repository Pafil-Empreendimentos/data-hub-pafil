# De-paras: inventário e como atualizar

Um "de-para" é uma tabela de mapeamento que o CVDW (a API do CRM) não fornece. Por
exemplo: qual escritório pertence a qual House, qual gerente responde por qual
corretor, ou qual canal de mídia agrupa quais parâmetros de UTM. Essas informações
vêm de planilhas mantidas manualmente pelo backoffice comercial, não da API.

Este documento explica onde cada de-para vive, como ele é carregado no banco e com
que frequência precisa ser atualizado. Para entender a regra de negócio por trás de
cada de-para, ou seja, a lógica que ele resolve, veja as seções `DP-*` de
[`regras-de-negocio.md`](regras-de-negocio.md). Para entender por que esse processo continua
manual mesmo com o banco em produção, veja a seção 4 de [`arquitetura.md`](arquitetura.md).

## A fonte única da verdade

O arquivo `config/deparas.yml` é o registro vivo de todos os de-paras: nome, tabela
correspondente na silver, tipo, caminho da planilha de origem (relativo a
`base_sharepoint`) e uma descrição. Ele é lido por `python -m ferramentas.montar_estrutura_depara`, que
materializa a estrutura versionada dentro de `<DEPARA_DIR>/depara_<nome>/`, a pasta
que o Power BI "BI V3 CVDW" também lê.

Isso significa que, ao criar ou alterar um de-para, o primeiro passo é sempre editar
o `.yml`. Este documento aqui é um resumo de leitura, pensado para consulta rápida,
não a fonte de verdade em si.

## Os tipos de de-para (campo `tipo` no yml)

| Tipo | O que significa | Exemplo |
|---|---|---|
| `arquivo` | Copia um arquivo `.xlsx` ou `.xlsm` já pronto, vindo do SharePoint | `dpara_gerente_contexto` |
| `silver` | Materializa uma tabela `silver.*` para Excel. A regra já está embutida no pipeline, sem depender de uma planilha externa | `dpara_ordem_etapa` |
| `gerado` | É produzido por um script do próprio projeto | `de_para_classificacao.xlsx`, gerado por `python -m ferramentas.gerar_depara_classificacao` |
| `pendente` | Documenta uma lacuna conhecida: ainda não existe uma fonte local carregada para esse de-para | (nenhum pendente no momento; veja `config/deparas.yml`) |

## Como recarregar cada de-para

Todos os carregadores (loaders) vivem dentro de `popular_seeds.py`, cada um com a sua
flag. Cada flag recebe o caminho da planilha. Quando a flag não é passada, o script usa o
caminho da variável correspondente do `.env` (por exemplo `DEPARA_GERENTES_XLSX`), e **só
carrega aquele de-para se o caminho existir**. Na prática:

- `python popular_seeds.py` sem nenhuma flag recarrega todos os de-paras cujo caminho está
  preenchido no `.env`. É o que se usa na rotina.
- Passar uma flag com um caminho recarrega aquele de-para a partir daquele arquivo.
- Cuidado ao passar a flag: ela espera o **caminho do arquivo**, não o nome da variável.
  `--leads-apoio LEADS_APOIO` faz o script procurar um arquivo chamado literalmente
  `LEADS_APOIO`, e o loader é pulado com só um aviso no log.

| Flag | O que carrega |
|---|---|
| `--gerentes <xlsx>` | `dpara_gerente_contexto` e `dpara_imobiliaria_house` (vêm da mesma planilha, em abas diferentes) |
| `--headcount-corretores <xlsx>` | `dpara_corretor_headcount`, a fonte autoritativa de equipe e gerente de cada corretor |
| `--leads-apoio <xlsm>` | `dpara_canal_midia`, `dpara_canal_midia_dc`, `dpara_ativo_receptivo` e `dpara_qualificacao_lead`, as quatro vindas de abas diferentes da planilha "Base de Leads" |
| `--etapa-precadastro <xlsm>` | `dpara_etapa_precadastro` |
| `--credito-manual <xlsx>` | o complemento manual de crédito, informação que não existe na API |
| `--xlsm <Vendas Consolidadas.xlsm>` | `dpara_empreendimento`, a partir da aba DE_PARA_PRODUTOS |
| `--estrutura-precos`, `--metas-empreendimentos`, `--metas-performance-digital`, `--viabilidade`, `--distratos-2025` | Preço e estoque, metas, viabilidade e o detalhe financeiro dos distratos (`d_estrutura`, `d_metas_*`, `d_viabilidade`, `distratos_2025`) |
| `--profissoes` | `dpara_profissoes` |
| `--ramais` | `dpara_ramais` (ramal para setor e responsável, usada na telefonia) |
| `--perfil-cliente-precadastro`, `--perfil-cliente-reserva` | Os CSVs de fallback do perfil de cliente |

A lista completa de variáveis está comentada no `.env.example`, e `python popular_seeds.py --help`
mostra todas as flags. `python aplicar_tudo.py` aplica silver, gold e seeds em uma execução só.

## Inventário completo

| De-para | Tabela em `silver.*` | Tipo | Fonte | Como recarregar |
|---|---|---|---|---|
| Gerentes (contexto da reserva) | `dpara_gerente_contexto` | arquivo | `Gerentes/depara_gerentes.xlsx` | `--gerentes` |
| Imobiliária para House/Regional | `dpara_imobiliaria_house` | arquivo | mesma planilha acima, aba "imobiliaria" | `--gerentes` |
| Equipe do corretor (headcount) | `dpara_corretor_headcount` | arquivo | `HeadCount/Base Corretores Pafil.xlsx` | `--headcount-corretores` |
| Empreendimento para regional, viabilidade e IVV | `dpara_empreendimento_regional` | arquivo | `Empreendimentos/d_para empreendimentos.xlsx` | manual, ainda sem loader |
| Metas mensais | (nenhuma tabela ainda) | arquivo | `Meta.xlsx` | integrado direto no Power BI, não passa pelo Postgres |
| Estrutura de preços | (nenhuma tabela ainda) | arquivo | `base_precos.xlsm` | não se aplica |
| Headcount por equipe e mês | (nenhuma tabela ainda) | arquivo | `depara headcount.xlsx` | não se aplica |
| Equipe do corretor (versão legada, do pré-cadastro) | `dpara_equipe_corretor` | arquivo | `Crédito/depara equipe corretor.xlsx` | sem loader de propósito: foi superada por `corretor_headcount` como fonte autoritativa em 21 de julho de 2026 |
| Canal e mídia (válido até outubro de 2024) | `dpara_canal_midia` | arquivo | `Base de Leads.xlsm`, aba Apoio | `--leads-apoio` |
| Canal e mídia D.C (chave por UTM, válido a partir de outubro de 2024) | `dpara_canal_midia_dc` | arquivo | mesma planilha, outra aba | `--leads-apoio` |
| Classificação oficial por proposta | (nenhuma tabela ainda) | gerado | `de_para_classificacao.xlsx`, via `python -m ferramentas.gerar_depara_classificacao` | rodar o gerador |
| Produto para nome conformado e EP | `dpara_empreendimento` | silver | aba DE_PARA_PRODUTOS da Vendas Consolidadas | `--xlsm` |
| Ativo, Receptivo ou Diretoria | `dpara_ativo_receptivo` | arquivo | `Base de Leads.xlsm`, aba Apoio | `--leads-apoio` |
| Qualificação do lead (MQL) | `dpara_qualificacao_lead` | arquivo | `Base de Leads.xlsm`, aba Apoio | `--leads-apoio` |
| Etapa ou situação para ordem do funil | `dpara_ordem_etapa` | silver | regra embutida no código, sem planilha | não se aplica |
| Situação da reserva para esteira | `dpara_situacao_esteira` | silver | regra embutida no código, sem planilha | não se aplica |
| Corretores fora do ranking (coordenação) | `dpara_corretor_fora_ranking` | silver | regra embutida no código, sem planilha | não se aplica |
| Responsável para imobiliária | `dpara_responsavel_imobiliaria` | silver | regra embutida no código, sem planilha | não se aplica |
| Etapa do pré-cadastro (funil de crédito) | `dpara_etapa_precadastro` | arquivo | `Crédito/Base - Crédito.xlsm`, aba Apoio | `--etapa-precadastro` |

## De quem é cada planilha de origem

Todas as planilhas de origem vivem no SharePoint do time Comercial (nas pastas
"BI - Comercial" e "Relatórios Comercial"), e são mantidas pelo backoffice
comercial. Quem precisar de acesso a alguma delas deve pedir diretamente ao time
comercial ou ao backoffice. O `.env` local de cada máquina aponta para a cópia
sincronizada via OneDrive, na máquina de quem roda os carregadores (veja
[`onboarding.md`](onboarding.md) para o passo a passo dessa configuração).
