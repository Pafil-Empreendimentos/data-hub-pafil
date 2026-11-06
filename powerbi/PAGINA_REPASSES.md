# Página "Repasses"

Sobre `gold.fato_repasses`, `gold.fato_repasses_etapas` e `gold.fato_repasses_movimentos`. As medidas
estão em [MEDIDAS_REPASSES.dax](MEDIDAS_REPASSES.dax). A análise por trás dos números, o caminho do
dado e a lista de armadilhas estão em [`docs/comissoes-e-repasses.md`](../docs/comissoes-e-repasses.md).

O repasse é a etapa em que o financiamento bancário do comprador é contratado, registrado e liberado
para a construtora. Esta página responde cinco perguntas: quanto da fila é trabalho de verdade e quanto
é espera, onde o repasse está parado, onde o processo demora, quem converte mais (correspondente e
empreendimento) e quais repasses a equipe precisa mexer hoje.

**HTML/CSS no design system das outras páginas** (fonte Segoe UI, azul `#003254`, cartão cinza para a
foto de hoje, vermelho para o que dói), com o visual HTML Content do AppSource. Esse visual **não executa
JavaScript**: o movimento (barras que crescem) e a interação (destaque ao passar o mouse, clique que
filtra a página) vêm de CSS puro e do campo Granularity. As medidas HTML foram conferidas com uma prévia
estática renderizada com os dados reais; **não foram testadas dentro do Power BI Desktop**, então confira
os visuais na primeira montagem.

## 0. Antes de montar

**Tabelas novas.** Elas não existem no `.pbix`. No Desktop: Obter dados, Banco de dados PostgreSQL,
servidor `localhost:5433` (túnel de produção, ver [README](README.md)), banco `pafil_dw`, usuário
`pafil_bi`, modo Importar. No Navegador, marque do schema `gold`: `fato_repasses`,
`fato_repasses_etapas`, `fato_repasses_movimentos`, `dim_repasse_etapa` e `dim_correspondente`.
**Crie as tabelas pela interface, nunca por XMLA ou pelo MCP**: tabela criada assim entra como consulta
que o editor do Power Query não conhece, e o Desktop deixa de salvar o arquivo. Medidas, por outro lado,
podem ir por XMLA (e lembre do Ctrl+S depois).

**Relacionamentos** (todos um para muitos; os fatos não se ligam entre si):

| De (lado 1) | Para (lado muitos) | Ativo |
|---|---|---|
| `dim_calendario[data]` | `fato_repasses[data_cad]` | sim |
| `dim_calendario[data]` | `fato_repasses[data_finalizacao]` | **não** (a série mensal o ativa com USERELATIONSHIP) |
| `dim_calendario[data]` | `fato_repasses_etapas[data_saida]` | sim |
| `dim_calendario[data]` | `fato_repasses_movimentos[data_movimento]` | sim |
| `dim_empreendimento[id_empreendimento]` | `fato_repasses`, `fato_repasses_etapas`, `fato_repasses_movimentos` (`id_empreendimento`) | sim |
| `dim_correspondente[correspondente]` | `fato_repasses`, `fato_repasses_etapas`, `fato_repasses_movimentos` (`correspondente`) | sim |
| `dim_repasse_etapa[id_situacao]` | `fato_repasses[id_situacao]` | sim |

**Classificar por coluna:** `dim_repasse_etapa[situacao]` por `ordem_exibicao`; `dim_repasse_etapa[fase]`
por `fase_ordem`; `fato_repasses[status_repasse]` por `status_repasse_ordem`. A faixa de dias
(`faixa_dias_na_etapa`) já vem numerada e ordena sozinha.

**Ocultar no modelo:** os `id_*`, `corretor_chave`, `eh_*` que só servem às medidas, e `ordem_exibicao`.
Nenhuma coluna de nome, documento ou telefone do cliente existe nestas tabelas.

Confirme que `dim_calendario` cobre o mês corrente (a gold a estende até 31/dez do ano atual): um
relacionamento de data fora do intervalo não dá erro, deixa tudo em branco.

## Layout (canvas 4500 x 3800, o mesmo das páginas de Atendimento)

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  1. Faixa de KPIs (HTML Content, 9 cartões)                              4420 x 200  │
├──────────────┬────────────────────────────────┬──────────────────────────────────────┤
│  Filtros     │  2. Fila por fase   1700 x 760 │  3. Aging            1700 x 640      │
│  (slicers)   ├────────────────────────────────┴──────────────────────────────────────┤
│              │  5. Série mensal, abertos x finalizados                    2400 x 640 │
├──────────────┴─────────────────────────┬─────────────────────────────────────────────┤
│  4. Tempo por etapa      1900 x 1500   │  6a. Por correspondente (clique) 2400 x 700 │
│                                        │  6b. Por empreendimento (clique) 2400 x 1050│
├────────────────────────────────────────┴─────────────────────────────────────────────┤
│  7. Repasses em tratativa, um por linha (HTML Content, clique)           4420 x 900  │
└──────────────────────────────────────────────────────────────────────────────────────┘
        Painel que abre por botão: 8. Como ler esta página (Critérios)        1100 x 900
```

## 1. Faixa de KPIs

**Visual:** HTML Content. **Values:** `[KPIs Repasses HTML]`.

Nove cartões. Azul é medida do período (data de abertura do repasse), cinza é a **foto de hoje** e
ignora o filtro de período, vermelho é o que dói.

| Cartão | Cor | Mede | Em 06/nov/2026 |
|---|---|---|---|
| REPASSES | azul | abertos no período | 3.440 |
| FINALIZADOS | azul | chegaram a Repasse Finalizado, com o financiado no subtítulo | 1.635, R$ 193,9 mi |
| CONVERSÃO | azul | finalizados ÷ (finalizados + cancelado, distrato e cessão) | 56,0% |
| CICLO MEDIANO | azul | mediana de dias da abertura à finalização, sem lotes | 151 d |
| EM TRATATIVA | cinza | a fila de trabalho (em andamento, fora das esperas) | 76, R$ 19,3 mi |
| EM ESPERA | cinza | Aguardando APF e Finan. Chaves | 445 |
| PARADOS | vermelho | em tratativa na mesma etapa há mais de 30 dias | 18 |
| RETRABALHO | vermelho | finalizados que passaram por etapa de pendência | 55% |
| PÓS-REPASSE | vermelho | finalizou e depois virou distrato ou cancelamento | 18 |

Cada cartão tem um balão (atributo `title`) com a definição, que o Power BI pode ou não exibir; nada
quebra se não exibir. O limite de "parado" é a medida `[Dias Para Considerar Parado]` (30).

## 2. Fila por fase

**Visual:** HTML Content. **Values:** `[Funil Repasses HTML]`. Foto de hoje.

As cinco fases da fila de trabalho em barras (Documentação e conformidade, Entrevista minuta e assinatura,
ITBI e cartório, Liberação de recursos, Pendências e exceções), cada uma com repasses, VGV e a média de
dias na etapa. Embaixo, separada, a espera por marco (APF e chaves), que é 85% do andamento e achataria as
barras. O agrupamento em fases é uma proposta, editável em `silver.repasses_situacoes`.

## 3. Aging

**Visual:** HTML Content. **Values:** `[Aging Repasses HTML]`. Foto de hoje.

Fases nas linhas, faixas de dias na etapa atual nas colunas, cor crescente com a quantidade. As faixas de
mais de 30 dias ficam em tom de vermelho. Em 06/nov/2026 a fila está saudável: dos 76 em tratativa, 37
estão há até 7 dias e só 18 passam de 30, metade deles em Pendências (6 há 91 a 180 dias).

## 4. Tempo por etapa

**Visual:** HTML Content. **Values:** `[Tempo Por Etapa Repasses HTML]`.

Mediana (barra escura) e p90 (barra clara) em dias, por etapa, só das passagens que terminaram no período.
Entram etapas com 30 passagens ou mais, sem as esperas por marco e sem as etapas que o CVCRM aposentou.
Os gargalos hoje são Recolhimento | ITBI (13,8 dias), Prenotado | Cartório (11,2), Emissão de Minuta e
Conferência (9,1) e as etapas de pendência (em vermelho). Tamanho recomendado 1900 x 1500: a lista tem
cerca de 25 etapas.

## 5. Série mensal

**Visual:** HTML Content. **Values:** `[Série Repasses HTML]`.

Os últimos 18 meses, abertos (azul, pela data de abertura) e finalizados (verde, pela data da última
mudança de situação). **Ignora o filtro de período** (o gráfico é o eixo do tempo) e respeita
empreendimento e correspondente. Atenção a picos de meses antigos: abril de 2024 (507 finalizações) é
limpeza em lote, e não produção. Os cartões e as tabelas excluem os lotes do ciclo, mas esta série mostra
tudo.

## 6. Tabelas com clique: correspondente e empreendimento

**Visual:** HTML Content com Granularity, uma linha por correspondente (6a) e por empreendimento (6b). O
clique filtra a página, e Ctrl+clique acumula.

| Campo do visual | 6a, correspondente | 6b, empreendimento |
|---|---|---|
| Values | `[Linha Correspondente Repasse HTML]` | `[Linha Empreendimento Repasse HTML]` |
| Granularity | `dim_correspondente[correspondente]` | `dim_empreendimento[empreendimento_conformado]` |
| Tooltips | `[Repasses por Linha (ordenação)]` | o mesmo |
| Classificar por | `Repasses por Linha (ordenação)`, decrescente | o mesmo |
| Formatar, Stylesheet, fx | `[CSS Tabela Repasses (linhas)]` | o mesmo |

Também: Cross-filtering ativado, Transparency 0, "No data message" = "Nenhum repasse no período
selecionado." Oito colunas: nome, repasses (com barra de volume), finalizados, sem repasse, conversão (pílula
verde a partir de 60%, cinza de 40% a 59%, vermelha abaixo; os cortes estão na variável `_classe` de
`[Células Repasses HTML]`), em andamento (foto de hoje), ciclo mediano e financiado.

Leitura: conversão baixa não é sempre desempenho. CCA Pafil tem 1% porque quase tudo dele está em espera
(234 em andamento), e Parc das Artes e Quinta da Boa Vista têm 0% por razões diferentes (65 repasses
em espera por marco, no primeiro; 128 distratos e cancelamentos e nenhum finalizado, no segundo).

## 7. Repasses em tratativa, um por linha

**Visual:** HTML Content com Granularity = `fato_repasses[id_repasse]`.

| Campo do visual | Valor |
|---|---|
| Values | `[Linha Repasse HTML]` |
| Tooltips | `[Dias Na Etapa (ordenação)]` |
| Classificar por | `Dias Na Etapa (ordenação)`, decrescente |
| Stylesheet | `[CSS Tabela Repasses Detalhe (linhas)]` |
| Filtro do visual | `fato_repasses[condicao_andamento]` = "Em tratativa" |

É a lista de trabalho do backoffice, dos que estão há mais tempo na mesma etapa para os mais recentes. A
reserva e a unidade identificam a venda no CVCRM; **nome e documento do cliente não aparecem**. A pílula
de "na etapa" é verde até 7 dias, cinza até o limite de parado e vermelha acima.

## 8. Como ler esta página (Critérios)

**Visual:** HTML Content num painel que abre por botão (o mesmo mecanismo do painel de Telefonia).
**Values:** `[Critérios Repasses HTML]`. Tamanho 1100 x 900. É o glossário: o que é repasse, em tratativa x em
espera, parado, conversão, ciclo e o que é lote, retrabalho, pós-repasse e as vendas a financiar sem
repasse, com os números do recorte atual.

## 9. Filtros (slicers)

| Filtro | Campo | Observação |
|---|---|---|
| Ano e mês | `dim_calendario` | período = data de abertura; a série e a foto de hoje o ignoram |
| Empreendimento | `dim_empreendimento[empreendimento_conformado]` | filtra os três fatos |
| Correspondente | `dim_correspondente[correspondente]` | filtra os três fatos |
| Modalidade | `fato_repasses[modalidade_financiamento]` | MCMV, PAFIL, SBPE; **só filtra fato_repasses** |
| Tipo de venda | `fato_repasses[tipo_venda_repasse]` | Financiamento na Planta, Financiamento Chaves, Venda Direta, Venda à Vista; só fato_repasses |
| Condição | `fato_repasses[condicao_andamento]` | Em tratativa, Em espera por marco, Encerrado; só fato_repasses |

Os três últimos não chegam a `fato_repasses_etapas` e `fato_repasses_movimentos` (desenho galaxy: fato não
se liga em fato). Se a página precisar deles nesses dois visuais, o caminho é criar uma dimensão
compartilhada, e não ligar os fatos.

## 10. Como validar depois de montar

Sem filtros, devem aparecer (06/nov/2026, a produção muda a cada hora): Repasses 3.440, Finalizados 1.635,
Conversão 56,0%, Em tratativa 76 (VGV R$ 19.296.504), Em espera 445, Parados 18, Ciclo mediano 151 dias
(p90 500, sobre 816 repasses), Pós-repasse 18, Financiado finalizado R$ 193.931.670. Funil: 47, 9, 4, 2 e 14
repasses nas cinco fases e 445 na espera. Por correspondente: REM Negocios 714 repasses e 64% de
conversão; Finance Assessoria 653 e 63%; RM Assessoria Imobiliária 442 e 47%. Se um desses não bater, o
relacionamento ou o filtro de página é o primeiro suspeito (um filtro de página em `condicao_andamento` ou
em `eh_ciclo_confiavel` distorce os cartões, como aconteceu na página de Telefonia).

## 11. O que a página não mostra, e por quê

- **Valor financiado antes de 2025.** Os repasses de 2023 e 2024 vieram da migração para o CVCRM e 629 dos
  finalizados deles têm os valores zerados. O VGV (valor do contrato) vem em todos.
- **Banco e agência.** Só 37 dos 3.440 repasses têm banco, então não há corte por banco.
- **Datas de assinatura, registro e liberação do recurso.** Vêm vazias em quase todos os repasses; o
  caminho do repasse é medido pelo histórico de situações, que é completo.
- **SLA por etapa.** Existe só na rota operacional `GET /v1/financeiro/repasses` (campo
  `sla_prazo_repasse`), que traz dado pessoal do cliente e não foi ingerida.
- **Repasses por pessoa.** `fato_repasses_movimentos` tem o responsável de cada mudança, mas a página mostra
  equipe x correspondente, e não ranking de funcionário. Se a gestão quiser, é uma tabela a mais sobre essa
  fato.
