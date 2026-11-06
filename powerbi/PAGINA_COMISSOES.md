# Página "Comissões"

Sobre `gold.fato_comissoes`, `gold.fato_comissoes_pagamentos`, `gold.fato_comissoes_programacao` e
`gold.fato_comissoes_regras`. As medidas estão em [MEDIDAS_COMISSOES.dax](MEDIDAS_COMISSOES.dax). A análise
por trás dos números, o caminho do dado e a lista de armadilhas estão em
[`docs/comissoes-e-repasses.md`](../docs/comissoes-e-repasses.md).

A reserva tem regras de comissão (quem recebe, quanto). Na venda o CVCRM gera a comissão, que percorre um
workflow de sete situações e se desdobra em pagamentos com vencimento. Esta página responde cinco
perguntas: quanto a Pafil deve de comissão e a que custo sobre o VGV, onde estão as comissões no processo,
quanto está parado esperando nota fiscal, quanto vence nos próximos meses e para quem vai a comissão.

**Um aviso antes de tudo: finalizada não é paga.** O CVCRM não registra o pagamento efetivo da comissão
(nenhum pagamento está na situação PAGO). A página mostra o que é **devido** e o que está **programado**,
e nunca "pago". Quem precisar do que saiu do caixa depende do financeiro (MEGA) ou da permissão da rota
de parcelas do CVCRM (hoje HTTP 403).

**HTML/CSS no design system das outras páginas**, com o visual HTML Content do AppSource, que **não executa
JavaScript**: movimento e interação vêm de CSS puro e do campo Granularity. As medidas HTML foram
conferidas com uma prévia estática renderizada com os dados reais; **não foram testadas dentro do Power BI
Desktop**, então confira os visuais na primeira montagem.

## 0. Antes de montar

**Tabelas novas.** No Desktop: Obter dados, Banco de dados PostgreSQL, servidor `localhost:5433` (túnel de
produção, ver [README](README.md)), banco `pafil_dw`, usuário `pafil_bi`, modo Importar. Do schema `gold`:
`fato_comissoes`, `fato_comissoes_pagamentos`, `fato_comissoes_programacao`, `fato_comissoes_regras`,
`dim_comissao_situacao` e `dim_imobiliaria`. **Crie as tabelas pela interface, nunca por XMLA ou pelo MCP**
(a tabela entra como consulta que o editor do Power Query não conhece e o Desktop deixa de salvar o arquivo).
Medidas podem ir por XMLA, com Ctrl+S depois.

**Relacionamentos** (um para muitos; os fatos não se ligam entre si):

| De (lado 1) | Para (lado muitos) | Ativo |
|---|---|---|
| `dim_calendario[data]` | `fato_comissoes[data_venda]` | sim |
| `dim_calendario[data]` | `fato_comissoes[data_cad]` e `[data_finalizacao]` | não |
| `dim_calendario[data]` | `fato_comissoes_pagamentos[vencimento]` | sim |
| `dim_calendario[data]` | `fato_comissoes_programacao[data_previsao]` | sim |
| `dim_calendario[data]` | `fato_comissoes_regras[data_venda]` | sim |
| `dim_empreendimento[id_empreendimento]` | os quatro fatos (`id_empreendimento`) | sim |
| `dim_imobiliaria[imobiliaria]` | os quatro fatos (`imobiliaria`) | sim |
| `dim_comissao_situacao[id_situacao]` | `fato_comissoes[id_situacao]` | sim |
| `dim_corretor_headcount[corretor_chave]` | `fato_comissoes[corretor_chave]` (opcional, para equipe e gerente) | sim |

**Classificar por coluna:** `dim_comissao_situacao[grupo]` por `grupo_ordem`; `fato_comissoes[grupo_situacao]`
por `grupo_situacao_ordem`. A faixa de vencimento dos pagamentos já vem numerada.

**Ocultar no modelo:** os `id_*`, `corretor_chave` e os `eh_*` que só servem às medidas. Nome, documento e CEP
do cliente não existem nestas tabelas.

## Layout (canvas 4500 x 3800, o mesmo das páginas de Atendimento)

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  1. Faixa de KPIs (HTML Content, 9 cartões)                              4420 x 200  │
├──────────────┬────────────────────────────────┬──────────────────────────────────────┤
│  Filtros     │  2. Situações   1700 x 700     │  4. Quem recebe      1700 x 760      │
│  (slicers)   ├────────────────────────────────┴──────────────────────────────────────┤
│              │  3. Cronograma dos próximos 18 meses                       2400 x 640 │
├──────────────┴───────────────────────────────┬───────────────────────────────────────┤
│  5a. Por imobiliária (clique)    2400 x 1000 │  6. NF pendente (clique)   3600 x 1200 │
│  5b. Por empreendimento (clique) 2400 x 800  │                                        │
└──────────────────────────────────────────────┴───────────────────────────────────────┘
        Painel que abre por botão: 7. Como ler esta página (Critérios)       1100 x 900
```

## 1. Faixa de KPIs

**Visual:** HTML Content. **Values:** `[KPIs Comissões HTML]`.

Azul é medida do período (data da venda), cinza é a **foto de hoje** (ignora o filtro de período) e
vermelho é o que dói.

| Cartão | Cor | Mede | Em 06/nov/2026 |
|---|---|---|---|
| COMISSÃO DEVIDA | azul | comissões não canceladas e com valor | R$ 20,3 mi, 1.581 comissões |
| % EFETIVO | azul | comissão devida ÷ VGV das vendas | 4,9% |
| FINALIZADAS | azul | situação Finalizado (não é paga) | R$ 15,7 mi, 1.205 |
| EM ABERTO | cinza | em apuração, esperando nota fiscal ou nota lançada | R$ 4,7 mi, 376 |
| CANCELADAS | cinza | valor cancelado, com a parte do gerado no subtítulo | R$ 10,3 mi, 34% |
| NF PENDENTE | vermelho | esperando a nota fiscal, inclusive de corretor desligado | R$ 2,8 mi, 223 |
| VIVAS S/ VENDA | vermelho | não cancelada, de reserva que virou distrato, cancelou ou venceu | R$ 1,8 mi, 135 |
| VENCE 12 MESES | azul | cronograma previsto das reservas vendidas | R$ 3,7 mi |
| VENCE 30 DIAS | azul | idem, próximos 30 dias | R$ 109 mil |

## 2. Situações

**Visual:** HTML Content. **Values:** `[Funil Comissões HTML]`. Segue o filtro de período.

As seis situações do workflow na ordem do processo, com quantidade, valor e, para as que ainda andam, a
mediana de dias na situação. Vermelho é o que espera a nota fiscal (Aguardando NF e Desligamento), verde é
finalizada e cinza é cancelada. As comissões de valor zero (cascas) ficam fora e aparecem numa nota ao
final. Hoje: a mediana de espera é de 585 dias em apuração, 826 em Aguardando NF e 402 nas de corretor
desligado.

## 3. Cronograma dos próximos 18 meses

**Visual:** HTML Content. **Values:** `[Fluxo Desembolso Comissões HTML]`. Ignora o filtro de período e
respeita imobiliária e empreendimento.

O que as reservas vendidas prometem pagar, mês a mês, pela data de previsão do cronograma. À esquerda, o
que já venceu antes deste mês (R$ 13,7 mi, sem como saber se foi pago); à direita, o que vence depois da
janela. Se um mês passa de 3 vezes o segundo maior, a barra dele é cortada (listrada) e o valor fica escrito
embaixo: hoje é agosto de 2027 (R$ 3,0 mi em 518 parcelas, ligadas à entrega), e sem o corte ele achataria
todos os outros meses.

## 4. Quem recebe

**Visual:** HTML Content. **Values:** `[Estrutura Comissão HTML]`. Segue o filtro de período.

Em quanto do contrato a comissão se divide, por tipo de beneficiário, nas regras ativas das reservas
vendidas: 4,9% no total, sendo 4,18% a imobiliária, 0,64% o corretor, 0,04% a equipe interna da Pafil e
0,02% o usuário da imobiliária. O percentual de cada grupo é sobre o VGV de todas as reservas com regra
(cada reserva contada uma vez).

## 5. Tabelas com clique: imobiliária e empreendimento

**Visual:** HTML Content com Granularity. O clique filtra a página (Ctrl+clique acumula).

| Campo do visual | 5a, imobiliária | 5b, empreendimento |
|---|---|---|
| Values | `[Linha Imobiliária Comissão HTML]` | `[Linha Empreendimento Comissão HTML]` |
| Granularity | `dim_imobiliaria[imobiliaria]` | `dim_empreendimento[empreendimento_conformado]` |
| Tooltips | `[Comissão por Linha (ordenação)]` | o mesmo |
| Classificar por | `Comissão por Linha (ordenação)`, decrescente | o mesmo |
| Stylesheet | `[CSS Tabela Comissões (linhas)]` | o mesmo |

Também: Cross-filtering ativado, Transparency 0, "No data message" = "Nenhuma comissão no período
selecionado." e filtro do visual `[Comissão Devida]` diferente de vazio. Oito colunas: nome (com House ou
Parcerias ao lado, na tabela por imobiliária), comissões devidas (com barra de volume), VGV, comissão, % efetivo,
finalizada, em aberto (foto de hoje) e cancelada (parte do gerado). A pílula do % efetivo é verde na média do
recorte ou abaixo, cinza até 0,5 ponto percentual acima e vermelha acima disso (a média é a do conjunto de
linhas que o filtro deixa; os cortes estão em `_classe` de `[Células Comissões HTML]`).

Leitura: a House **não** é uniformemente mais barata. Ribeirão Preto fica em 4,4%, mas São Carlos e
Uberaba, também House, ficam em 5,9% e 6,0%, no patamar das parceiras.

## 6. Nota fiscal pendente, uma comissão por linha

**Visual:** HTML Content com Granularity = `fato_comissoes[id_comissao]`.

| Campo do visual | Valor |
|---|---|
| Values | `[Linha NF Pendente HTML]` |
| Tooltips | `[Dias Na Situação (ordenação)]` |
| Classificar por | `Dias Na Situação (ordenação)`, decrescente |
| Stylesheet | `[CSS Tabela NF Pendente (linhas)]` |
| Filtros do visual | `fato_comissoes[eh_em_aberto]` verdadeiro e `fato_comissoes[grupo_situacao]` em "2. Aguardando NF" e "3. Desligamento, NF pendente" |

É a lista de cobrança: reserva, imobiliária, corretor, empreendimento, situação, valor e há quanto tempo
espera (pílula cinza até 90 dias, cinza escuro até um ano e vermelha acima). Mostra quem precisa emitir a
nota, e não o cliente. É carteira antiga (mediana acima de um ano): a ação é cobrar ou dar baixa contábil.

## 7. Como ler esta página (Critérios)

**Visual:** HTML Content num painel que abre por botão. **Values:** `[Critérios Comissões HTML]`. Tamanho
1100 x 900. Explica regra, comissão e pagamento, devida, % efetivo, cancelada, NF pendente, vivas sem venda,
cascas e, em destaque, por que finalizada não é paga.

## 8. Filtros (slicers)

| Filtro | Campo | Observação |
|---|---|---|
| Ano e mês | `dim_calendario` | período = data da venda; as fotos de hoje e o cronograma o ignoram |
| Empreendimento | `dim_empreendimento[empreendimento_conformado]` | filtra os quatro fatos |
| Imobiliária | `dim_imobiliaria[imobiliaria]` | filtra os quatro fatos |
| House ou Parcerias | `dim_imobiliaria[house_parcerias]` | filtra os quatro fatos |
| Situação | `dim_comissao_situacao[grupo]` | só fato_comissoes |
| Status | `fato_comissoes[status_comissao]` | Em andamento, Finalizada, Cancelada, Sem valor apurado; só fato_comissoes |

## 9. Como validar depois de montar

Sem filtros, devem aparecer (06/nov/2026, a produção muda a cada hora): Comissão devida R$ 20.348.896,43 em
1.581 comissões, VGV R$ 416.983.940, % efetivo 4,88%, Finalizada R$ 15.656.495,87 (1.205), Em aberto
R$ 4.692.400,56 (376), Cancelada R$ 10.327.274,50, NF pendente R$ 2.809.069,28 (223), Vivas sem venda
R$ 1.837.924,39 (135), Vence em 12 meses R$ 3.682.954 e em 30 dias R$ 109.087, Já venceu R$ 13.715.099, e 1.284
comissões sem valor apurado. A conferência da página é: devida = finalizada + em aberto (20.348.896 =
15.656.496 + 4.692.401, sem filtro de período). Se algo não bater, o filtro de página é o primeiro
suspeito.

## 10. O que a página não mostra, e por quê

- **Comissão paga e data de pagamento.** Não existem no CVCRM (ver o aviso no topo).
- **Prêmio.** Todas as regras ativas hoje são do tipo comissão; a estrutura aceita prêmio e prêmio extra
  quando aparecerem.
- **Nome de quem recebe.** A estrutura mostra o tipo de beneficiário. Resolver o usuário administrativo
  exigiria ingerir `usuarios_administrativos` (211 linhas, com dado pessoal).
- **Cliente.** Nome, documento e CEP do cliente não entram em nenhum objeto.
- **Comissão por gerente de venda.** Pode ser feita ligando `dim_corretor_headcount[corretor_chave]` a
  `fato_comissoes[corretor_chave]`. Não foi usado o "Gerente Responsável" da reserva porque a silver hoje
  devolve o valor mais antigo desse campo (R28 em [`docs/regras-de-negocio.md`](../docs/regras-de-negocio.md)).
