# Contexto do projeto

Este texto é para quem chega sem conhecer a história: por que a plataforma existe, o que já
está pronto e o que ainda falta. É o primeiro documento a ler depois do
[`README`](../README.md) e do [onboarding](onboarding.md).

## Por que o projeto existe

A Pafil é uma construtora e incorporadora, e o que move a empresa é venda. O BI comercial
funcionava assim: todo dia alguém exportava um CSV do CRM para o SharePoint, que alimentava
consultas no Power Query e medidas em DAX dentro de três relatórios (PBIX) diferentes. Os três
já divergiam entre si, e o fechamento do mês dependia de planilhas preenchidas à mão.

O destino é uma arquitetura em camadas: os dados saem do CVCRM pela API CVDW, passam por
Python, chegam a um banco PostgreSQL organizado em bronze, silver e gold, e terminam no
Power BI. O princípio que guia o trabalho é simples de dizer e trabalhoso de cumprir: toda
medida DAX, todo de-para e toda transformação do sistema antigo é uma regra de negócio em
potencial. Cada uma precisa ser mapeada, documentada e migrada com cuidado, sempre em busca
de um número oficial único.

O entregável final é a apresentação mensal de fechamento (a "Reunião de Fechamento"), feita
para gestores, corretores, SDRs, diretoria e marketing. As análises que a compõem são: vendas
acumuladas no ano, vendas por mês, por empreendimento, por mídia, a segmentação por House e
os rankings de corretores e de gerentes (por VGV e por unidades).

### A cadeia manual que a plataforma substitui

1. Todo dia, alguém extrai dados do CVCRM e cola numa planilha base. Colunas adicionais
   ("pintadas de cinza") são preenchidas à mão, seguindo regras de negócio. O resultado
   alimenta a planilha **Vendas Consolidadas**.
2. O financeiro envia por e-mail a planilha com os distratos reais do mês, já validada e
   extraída do MEGA.
3. Os distratos são confrontados à mão com a Vendas Consolidadas, e os ajustes são feitos
   manualmente.
4. A Vendas Consolidadas, já validada, alimenta o PBIX, que alimenta a apresentação.

O MEGA é o sistema central da empresa (financeiro, contabilidade e a maior parte dos
processos internos), mas o time de dados não tem acesso direto ao banco dele, só à interface
e a relatórios prontos. Por isso o BI comercial sempre dependeu do CVCRM somado a planilhas.

A plataforma automatiza a perna **CVCRM para Vendas Consolidadas**. A conferência dos
distratos vindos do financeiro e algumas regras manuais continuam, por enquanto, como passo
humano.

## De onde vêm os dados

| Fonte | Como chega | Observações |
|---|---|---|
| **CVCRM** (CRM imobiliário, `pafil.cvcrm.com.br`) | API CVDW, 22 objetos listados em [`config/objetos.yml`](../config/objetos.yml) | 500 registros por página e limite de cerca de 20 requisições por minuto. Passar disso gera erro 429 e bloqueio de 60 segundos. Autenticação por e-mail e token. A carga incremental usa `a_partir_data_referencia` |
| **Blip** (atendimento por WhatsApp) | API de comandos do Blip | A API só guarda cerca de 5 semanas de tickets, então o nosso banco é a única memória de longo prazo desse dado. Atrasar a carga é perder dado |
| **MDnet** (telefonia: PABX, URA e ramais) | Painel web, sem API. O extrator faz login e baixa o mesmo CSV do botão de exportar | Raspagem de painel: se o layout mudar, a carga falha. Detalhes em [`sql/silver/README.md`](../sql/silver/README.md) |
| **Planilhas do backoffice** | Leitura de arquivos `.xlsx` e `.xlsm` do SharePoint | De-paras, metas, preços, headcount. Não existem na API. Ver [`de-paras.md`](de-paras.md) |

A API do CVDW só devolve o estado atual dos dados. Por isso a bronze guarda, além da tabela
atual, um snapshot diário de cada objeto. É esse histórico que permite análises ao longo do
tempo.

## O que já está pronto

- **Bronze**: uma tabela crua por objeto, mais a tabela de snapshot de cada uma, para CVCRM,
  Blip e MDnet. A carga é idempotente (rodar duas vezes no mesmo dia não duplica nada).
- **Silver**: views que conformam e tipam os dados e calculam as flags de cada regra de
  negócio, mais as tabelas `dpara_*` carregadas das planilhas.
- **Gold**: o modelo em estrela para o Power BI. Fatos: `fato_reservas`, `fato_leads`,
  `fato_precadastros`, `fato_atendimentos` (Blip), `fato_atendimentos_cvcrm`, `fato_chamadas`
  (telefonia) e `fato_headcount_mensal`. Dimensões: calendário, empreendimento, unidade,
  corretor, origem (canal e mídia), perfil de cliente, estrutura e preço, metas, viabilidade,
  entre outras. O desenho está em [`modelo-semantico.md`](modelo-semantico.md).
- **Power BI**: o relatório "BI Matriz V3" já consome a gold. As medidas e o roteiro de cada
  página estão em [`powerbi/`](../powerbi/README.md): Vendas, Marketing, Esteira, Pré-cadastro
  (crédito), Preço e estoque, Performance dos corretores, Perfil do cliente, Atendimento
  (Blip e CVCRM) e Telefonia.
- **Produção**: banco de pé desde 20/ago/2026, com backup diário e as cargas agendadas
  descritas no [`README`](../README.md) e em [`infra/README.md`](../infra/README.md).

## A regra mais importante: R1

A palavra "venda" tem duas definições no sistema antigo. Uma considera só a situação
`Vendida`. A outra considera `Vendida` e `Distrato` juntas. A plataforma expõe as duas
(`eh_venda` e `eh_venda_ou_distrato`), mas decidir qual é a oficial não é questão técnica: é
decisão da gestão.

## Reconciliações: a prova de que funciona

As reconciliações comparam número a número a plataforma com o sistema antigo. Os relatórios
completos estão em [`reconciliacao/`](../reconciliacao/).

- **Distratos de maio de 2026**: batem ao centavo. São 54 distratos dos dois lados, com o mesmo
  VGV de R$ 12.888.599,11.
- **Vendas**: o `valor_contrato` da API é idêntico ao "VGV (Praticado)" da planilha em 1.869 de
  1.892 propostas (98,8%). Achados: 420 propostas que o fechamento manual ainda trata como
  venda viva já aparecem como Distrato no CRM (o fechamento manual anda sempre um pouco
  atrasado), e alguns status usados à mão na planilha (`Validada`, `Venda distratada`,
  `Repassada`, `Envio Mega`) não existem na API, porque pertencem a uma camada de
  reclassificação manual.

## Estado atual e próximos passos

**Em aberto de verdade**

- Refazer a reconciliação de totais com a carga completa de produção. As primeiras
  reconciliações só eram válidas por chave (proposta a proposta), porque a carga local era
  parcial.
- Validar com a gestão as regras ainda pendentes: R1 (definição oficial de venda), R3 (qual
  versão de canal e mídia usar), R6 (listas de exceção) e R9 e R10 (status manuais e o atraso
  do fechamento). Veja [`regras-de-negocio.md`](regras-de-negocio.md).
- Investigar as 23 divergências de VGV da reconciliação de vendas, que seguem um padrão de
  cerca de R$ 9,5 mil cada.
- Tornar a atualização dos de-paras menos manual. Hoje ela depende do notebook do analista
  com um túnel SSH. O plano é buscar as planilhas direto do SharePoint pela Microsoft Graph
  API ([`pedido-ti-graph-api.md`](pedido-ti-graph-api.md)). A exceção são os processos que
  dependem do Excel aberto (edição do headcount, que tem tabelas dinâmicas, e o fechamento
  mensal escrevendo na Vendas Consolidadas): esses continuam manuais.

**Planejado, ainda não implementado**

- Migrar bronze, silver e gold para dbt-core, com testes automatizados (hoje o projeto não
  tem testes).
- Trocar o Agendador de Tarefas do Windows por Airflow.
- Consolidar nesse mesmo alicerce a lógica do projeto
  [`integracao-cvcrm-ghl`](https://github.com/arturvillasboas/integracao-cvcrm-ghl).

O acompanhamento dessas frentes fica nas issues e no Project do GitHub deste repositório.

## Armadilhas conhecidas

- **`CREATE OR REPLACE VIEW` não deixa inserir ou renomear coluna no meio.** Só é possível
  adicionar colunas no final. Isso já causou retrabalho mais de uma vez.
- **O console do Windows usa cp1252.** Scripts que imprimem acentos ou setas precisam
  reconfigurar a saída para UTF-8. O `ferramentas/consultar.ps1` usa `PGCLIENTENCODING=WIN1252`
  por isso.
- **`openpyxl` está no `requirements.txt` de propósito.** Ele lê as planilhas dos seeds. Ficou
  de fora por um tempo e `popular_seeds.py` quebrou com `ModuleNotFoundError` na primeira
  execução em produção.
- **Locale `C` e acentos.** Num banco criado com locale `C`, `lower()` não trata letras
  acentuadas como esperado. Em comparações de texto com acento, use `COLLATE "und-x-icu"`.
- **Nunca reaproveite um token de API que já circulou fora de um `.env`.** Gere um novo. A
  política de rotação está em [`decisoes.md`](decisoes.md).
- **Dado pessoal exige cuidado redobrado.** Leads e pessoas têm telefone, e-mail e CPF
  reais. O banco só pode existir em infraestrutura da própria empresa.
