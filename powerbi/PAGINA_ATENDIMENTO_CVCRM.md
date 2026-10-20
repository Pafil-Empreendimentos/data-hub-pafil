# Página "Atendimento (CVCRM)"

Sobre `gold.fato_atendimentos_cvcrm`. As medidas estão em
[MEDIDAS_ATENDIMENTO_CVCRM.dax](MEDIDAS_ATENDIMENTO_CVCRM.dax).

**Não confundir com a página "Atendimento" já existente**
([PAGINA_ATENDIMENTO.md](PAGINA_ATENDIMENTO.md)), que é o chat de WhatsApp via
Blip. Esta página é o módulo de protocolo/ticket de pós-venda do próprio
CVCRM, assistência técnica, financeiro, renegociação de contrato, um
domínio diferente, sem nenhuma relação entre os dois fatos hoje. Ver DP-17 em
`docs/regras-de-negocio.md` para como o endpoint foi descoberto e integrado.

## Antes de montar

**Atualização de 08/out/2026:** o volume saiu de 10 para 329 atendimentos
(198 abertos em setembro, 121 em outubro, a maioria finalizada em minutos ou
poucas horas). Já dá para ter gráfico de distribuição, como a pizza de humor do
cliente (seção 5). O parágrafo abaixo descreve o motivo do layout enxuto da
primeira versão e fica como histórico.

**O volume ainda era muito baixo para valer um layout cheio de gráficos**: o
ambiente `pafil` tinha só 10 atendimentos no total (não é amostra, é a
população inteira, conferida direto na API). Com esse tamanho, qualquer
gráfico de série temporal ou ranking vai ter uma ou duas barras. Por isso o
layout abaixo é deliberadamente enxuto, uma faixa de KPIs e uma tabela de
detalhe, em vez de replicar o layout cheio da página de Blip. Ele foi
desenhado para crescer: as mesmas medidas e a mesma tabela detalhe continuam
válidas quando o volume aumentar, e é aí que valem visuais de tendência
(criados x finalizados por mês, ranking por empreendimento/assunto).

**HTML/CSS desde já, por decisão do analista responsável** (16/set/2026): mesmo com volume
baixo, a faixa de KPIs e a tabela de detalhe usam HTML Content, na mesma
linguagem visual das páginas de Blip e Performance (fonte, azul `#003254`,
cantos arredondados), para a página já nascer com a cara do resto do
relatório, em vez de precisar de um retrabalho de estilo quando o volume
crescer. As medidas HTML estão na seção "HTML/CSS" de
`MEDIDAS_ATENDIMENTO_CVCRM.dax`.

Confirme que a `dim_calendario` cobre o mês corrente antes de montar
(mesmo aviso da página de Blip: relacionamento de data "quebrado" por range
não dá erro nenhum, só fica tudo em branco).

## Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  1. Faixa de KPIs (HTML Content, 7 cartões)                          │
├──────────────────────────────────────────────────────────────────────┤
│  2. Slicers: Empreendimento · Situação · Assunto · Prioridade        │
├──────────────────────────────────────────────────────────────────────┤
│  3. Tabela de detalhe (HTML Content, 1 linha por atendimento)        │
├──────────────────────────────────────────────────────────────────────┤
│  4. Esteira (HTML Content, kanban, réplica da tela nativa do CVCRM) │
└──────────────────────────────────────────────────────────────────────┘
```

A esteira (seção 4) é opcional e pode virar uma página separada se a página
principal ficar muito cheia, ela replica uma tela inteira do CVCRM
("Andamento dos atendimentos"), então tem uma pegada visual própria, diferente
da faixa de KPIs + tabela.

## 1. Faixa de KPIs

**Visual:** HTML Content. **Medida:** `[KPIs Atendimento CVCRM HTML]`.

Sete cartões: TOTAL, EM ABERTO (cinza), FINALIZADOS, ENCERRADOS 1º CONTATO, TEMPO
PARA PEGAR, TEMPO DE ATENDIMENTO e TEMPO DE FINALIZAÇÃO. As cores seguem a mesma convenção da faixa de
Blip: cinza é a única foto do momento em vez de medida do período, e vermelho
fica reservado para a métrica que dói (hoje nenhum cartão usa; a classe `.r`
continua no CSS da medida).

**Mudança de 08/out/2026:** os cartões CANCELADOS e TX CANCELAMENTO saíram a pedido
da reunião e deram lugar a ENCERRADOS 1º CONTATO, na mesma posição. O cartão mostra
a contagem como valor grande (70) e a taxa no subtítulo ("21,3% dos
atendimentos"). O rótulo é "ENCERRADOS 1º CONTATO" e não "ENCERRADOS NO 1º
CONTATO" de propósito: com `max-width:75%` por causa do ícone, o texto mais longo
provavelmente quebraria em duas linhas e desalinharia o valor dos vizinhos (estimado
pelo tamanho dos outros rótulos, não testado na tela). As medidas
`[Atendimentos Cancelados]` e `[Taxa de Cancelamento]` continuam no modelo, só
saíram do cartão (o cancelamento ainda aparece como selo vermelho na tabela de
detalhe e como coluna nos gráficos por equipe).

Dois cuidados de leitura:

- `[Atendimentos Em Aberto]` (dentro da medida HTML) é uma foto do momento
  (`REMOVEFILTERS` no calendário), igual ao cartão equivalente da página de
  Blip, não soma com Finalizados + Cancelados dentro de um período filtrado.
- `[Tempo Médio de Finalização (horas)]` mostra "--" quando não há nenhum
  atendimento finalizado no filtro corrente. Não é erro de relacionamento.

**Mudança de 14/out/2026, pegar e atender:** a pedido do gestor comercial entraram TEMPO PARA PEGAR e
TEMPO DE ATENDIMENTO ao lado do TEMPO DE FINALIZAÇÃO. Valem só para atendimento finalizado. A
definição de cada um, os números e a origem do dado (endpoint `atendimentos/workflow/tempo`)
estão na seção 7.

**Mudança de 15/out/2026, mediana e não média:** os três cartões de tempo mostram a **mediana**
no valor grande ("17 min", "0 min", "57 min", em minutos até 1 h e em horas acima), e o
subtítulo diz o que ela mede ("mediana, até alguém assumir"). A média saiu da tela porque um
atendimento de fev/2024 (909 dias) a infla de 12 h para 65 h. Isso vale também para o cartão
TEMPO DE FINALIZAÇÃO, que antes mostrava a média em horas. **Atenção na apresentação:** medianas
não somam, então pegar + atender não dá finalizar (17 + 0 contra 57 min). Com médias dava. Cada
um dos três cartões tem um balão (atributo `title`) com a definição ao passar o mouse; se o
visual HTML Content removê-lo, nada quebra. As medidas dos cartões são `[Tempo Mediano de Pegar
(min)]`, `[Tempo Mediano de Atender (min)]` e `[Tempo Mediano de Finalização (min)]`. As medidas
de média (`[Tempo Médio de Pegar (horas)]`, `[Tempo Médio de Atender (horas)]` e
`[Tempo Médio de Finalização (horas)]`) seguem no modelo, só não aparecem na faixa.

**Mudança de 14/out/2026, avaliação:** o cartão AVALIAÇÃO saiu a pedido do gestor comercial. Só 1 de 441
atendimentos tinha avaliação, então a média do cartão se apoiava num caso só. As
medidas `[Avaliação Média]` e `[Qtd Avaliações]` continuam no modelo. **Em 15/out/2026 a
coluna AVALIAÇÃO também saiu da tabela de detalhe**, pelo mesmo motivo. O dado segue em
`fato_atendimentos_cvcrm[avaliacao]`, só não aparece mais na página.

**Tempo de finalização, em horas (mudança de 08/out/2026; desde 15/out o cartão
mostra a mediana, ver acima, e o que segue descreve a média).** O cartão mostrava
dias e foi trocado para horas a pedido da reunião. Junto, apareceu um erro de
unidade: `tempo_finalizado` vem do CVDW em **minutos**, não em segundos (bate
com `data_finalizado - data_cad` em 304 dos 304 finalizados), e o cálculo antigo
dividia por 86.400. O cartão dizia "0,1 dias" para uma média real de ~100 horas.
Valores de referência, já corretos: 24,5 h em setembro, 11,3 h em outubro, 100,6
h sem filtro de período. A **média** é puxada por poucos atendimentos que
ficaram semanas ou anos abertos (um de fev/2024, finalizado em ago/2026, tem
21.810 h sozinho); a **mediana** do mês é de ~1 h. Por isso o número sem filtro
parece alto: filtre por mês ou considere uma medida de mediana se a gestão
quiser o "tempo típico".

## 2. Slicers

**Painel "Filtros" (decisão de 08/out/2026, revisada em 13/out/2026).** A primeira
versão tinha quatro slicers soltos (empreendimento, situação, assunto,
prioridade). Passou a ser um painel lateral com seis slots, herdado da página de
Leads: três listas suspensas, uma lista em duas colunas, uma linha de três blocos
e uma lista alta. Os seis filtros, de cima para baixo:

| # | Slot (estilo) | Filtro | Campo | Valores em 13/out/2026 |
|---|---|---|---|---|
| 1 | Lista suspensa | Equipe | `fato_atendimentos_cvcrm[equipe]` | 5 equipes + em branco |
| 2 | Lista em 2 colunas | Assunto | `fato_atendimentos_cvcrm[assunto]` | 13 |
| 3 | Lista suspensa | Faixa de tempo | `fato_atendimentos_cvcrm[faixa_tempo_finalizacao]` | 173 / 73 / 49 / 42 / 14 + 30 não finalizados |
| 4 | Blocos (3 por linha) | Status | `fato_atendimentos_cvcrm[status_atendimento]` | Em aberto 20, Finalizado 351, Cancelado 10 |
| 5 | Lista suspensa | Responsável | `fato_atendimentos_cvcrm[responsavel]` | 9 pessoas + em branco |
| 6 | Lista alta | Empreendimento | `fato_atendimentos_cvcrm[empreendimento_conformado]` | 18 + em branco |

**Critério da escolha:** o painel cobre o que os gráficos da página **não** filtram
por clique. Assunto, Humor e Situação já se filtram clicando na barra do assunto,
na rosca e nas colunas por equipe, então Situação e Humor saíram do painel. Status,
Faixa de tempo e Equipe não existem em nenhum gráfico clicável.

**Status** (`status_atendimento`, na gold desde 13/out/2026) junta os cinco valores
de `situacao` em três, com a mesma regra dos cartões: Cancelado é
`situacao = 'Cancelado'`, Finalizado é `eh_finalizado` e o resto é Em aberto.
`status_atendimento_ordem` (1 Em aberto, 2 Finalizado, 3 Cancelado) existe para
ordenar: no Power BI, selecione `status_atendimento` e use Classificar por coluna.

**Faixa de tempo** (`faixa_tempo_finalizacao`, na gold desde 13/out/2026) usa os
minutos de `tempo_finalizado` com cortes em 60, 240, 1.440 e 10.080 e limite
inferior inclusivo: "1 - Menos de 1 h", "2 - 1 a 4 h", "3 - 4 a 24 h", "4 - 1 a 7
dias", "5 - 7 dias ou mais" e "6 - Não finalizado" (em aberto e cancelado, que não
têm tempo). Escolher as faixas 1 a 5 tira da página os atendimentos em aberto e os
cancelados. O número na frente do rótulo faz a ordem alfabética coincidir com a
ordem das faixas.

Empreendimento usa a coluna da fato (só traz quem tem atendimento) e não
`dim_empreendimento` (traria todos os empreendimentos, quase todos vazios aqui).

**Campos avaliados e descartados:**

- `prioridade`: 327 de 329 são "Normal". Um filtro quase sempre inútil, saiu.
- `tipo` ("Aberto pelo cliente"/"pelo gestor", 322/7) e `origem` ("GE"/"PC",
  322/7): 98% num valor só. Não use `origem` como slicer de negócio: é um código
  de 2 letras, não canal de marketing, e não deve ser confundido com a
  origem/mídia de leads (domínio diferente, ver `gold.dim_origem`).
- `canal`: Whatsapp 273, Email 28, Telefone 5, Presencial 2 e 21 em branco. 83% num
  valor só.
- `subassunto`: 36 valores, grande demais para os slots.
- Fora do painel, mas úteis se sobrar espaço: "Encerrado no 1º contato"
  (`eh_resolvido_primeiro_contato`, Sim/Não) e Ano (`dim_calendario[ano]`).

**Uma interação a ajustar** (Formatar > Editar interações): o slicer de **Equipe**
não deve afetar os gráficos por equipe (seção 6, hoje quatro: Atendimento,
Contratos e Cobrança, Repasse e Assistência Técnica). Eles têm filtro fixo no nível
do visual, então escolher "Repasse" esvaziaria os outros três.

Atenção aos botões de mês do topo: se o campo deles for só o mês (sem o ano),
clicar em "setembro" mistura os 4 atendimentos de setembro/2025 com os 198 de
setembro/2026. Não conferi qual campo o slicer usa; o filtro de Ano, citado acima,
resolve se for o caso.

## 3. Tabela de detalhe (com clique)

**Visual:** HTML Content, configurado para o clique numa linha filtrar o
resto da página (igual à tabela do Blip), o que exige o campo Granularity
preenchido, e não só Values. Sem Granularity, o visual recebe o HTML inteiro
de uma vez, como um texto único, e clicar não faz nada; é a diferença entre
esta versão e a tabela estática que veio antes dela.

Configuração do visual:

| Campo | Valor |
|---|---|
| Values | `[Linha Atendimento CVCRM HTML]` |
| Granularity | `fato_atendimentos_cvcrm[id_atendimento]` |
| Tooltips | `[Data do Atendimento CVCRM (ordenação)]` |
| Classificar por | Data do Atendimento CVCRM (ordenação), decrescente |
| Formatar > Stylesheet > fx | `[CSS Tabela Atendimentos CVCRM]` |
| Formatar > Cross-filtering | Ativar, Transparency 0 |
| Formatar > No data message | "Nenhum atendimento no período selecionado." |

Colunas: protocolo, data, empreendimento, cliente, assunto, situação (com
selo colorido: vermelho para Cancelado, verde para Finalizado, cinza para as
demais), equipe e **pegar, atender e finalização** (desde 15/out/2026). A coluna avaliação
saiu na mesma data.

As três colunas de tempo mostram o valor **do atendimento daquela linha**, em minutos até 1 h,
em horas até 1 dia e em dias acima ("31 min", "3,5 h", "908,7 d"). O atendimento ainda aberto
mostra "--" nas três, porque pegar e atender só existem para o finalizado. Aqui o valor é o
exato de cada atendimento, e não a mediana dos cartões. A tabela tem 10 colunas, e o CSS
`[CSS Tabela Atendimentos CVCRM]` declara isso em `repeat(10,auto)` (eram 8 até 15/out/2026,
11 por algumas horas, com a avaliação). Se uma coluna entrar ou sair um dia, esse número muda
junto, senão a grade desalinha.

**Por que Granularity é o campo `id_atendimento`, e não `protocolo`:** é a
chave técnica do grão do fato, uma linha da tabela é sempre um atendimento,
nunca dois com o mesmo id, então o clique nunca ambiguiza qual registro foi
selecionado. `protocolo` até funcionaria hoje (também é único), mas
`id_atendimento` é a chave de verdade do modelo.

Com 10 linhas, a tabela de detalhe carrega mais peso analítico do que os
cartões, é nela que a gestão consegue de fato ler cada ticket, o que os
agregados ainda não sustentam sozinhos. E com o clique ativo, selecionar uma
linha já filtra a faixa de KPIs pra aquele atendimento específico, útil pra
conferir um caso pontual sem sair da página.

## 4. Esteira (kanban)

Réplica da tela nativa "Andamento dos atendimentos" do CVCRM: 6 colunas fixas,
**na ordem certa agora** (Novo Atendimento → Triagem → Time Cobrança → Time
Atendimento → Time Crédito → Em Atendimento, o `ASC` por nome da primeira
versão embaralhava isso alfabeticamente, corrigido), cabeçalho na cor da
paleta de KPIs (azul `#003254` na primeira coluna, vermelho `#8A1C1C` nas
demais, mesma paleta da faixa de KPIs da seção 1, pedido de harmonia
visual), e um cartão por atendimento com protocolo, cliente, bloco/unidade +
empreendimento, assunto/subassunto e um rodapé "+ INFORMAÇÕES". Cancelado e
Finalizado ficam de fora, a tela nativa mostra o que está em andamento, não
o histórico encerrado. Fontes bem maiores que o resto do arquivo, calibradas
pro tamanho real desta página (4500×3800) e deste visual (4253 de largura ×
876 de altura, ~708px por coluna).

**Passe o mouse sobre um cartão** para expandir um bloco de estatísticas:
CRIADO HÁ, NA SITUAÇÃO, INTERAÇÕES, ÚLT. ATUALIZAÇÃO, inspirado na tela
expandida de um exemplo recebido. As três linhas de "VENCIMENTO DE SLA"
daquele print (por assunto/subassunto/workflow) **não entraram**: o endpoint
`atendimentos` do CVDW não traz prazo de SLA em nenhum dos 60 campos. **Atualização
de 14/out/2026:** o SLA existe em outra rota da API, `relacionamento/atendimentos/listar`
(`slaAssunto`, `dataVencimentoAssunto`, `slaSubassunto`, `slaWorkflow`,
`dataVencimentoWorkflow`, ver seção 7). Falta só decidir se vale ingerir essa rota.

**Confirmado em 14/out/2026:** as 6 colunas são valores do campo
`fato_atendimentos_cvcrm[situacao]`. Na primeira versão isso era uma aposta (só
"Em Atendimento" existia nos 10 registros de então, e os outros cinco nomes vinham
da captura de tela do CVCRM). Agora, com 430 atendimentos, os seis aparecem no
banco com a grafia exata da tabela `Esteira Colunas`, e com ids que já crescem na
ordem do quadro: Novo Atendimento 1, Triagem 8, Time Cobrança 9, Time Atendimento
10, Time Crédito 11 e Em Atendimento 12. Ou seja, "Time Cobrança", "Time
Atendimento" e "Time Crédito" são situações próprias e não uma combinação de
situação com equipe.

**Ordem das situações nos gráficos.** Fora do quadro, a ordem natural é a do
fluxo, com Finalizado e Cancelado por último. A gold tem a coluna
`situacao_ordem` para isso (etapas pelo id do CVCRM, Finalizado 98 e Cancelado 99;
situação nova do CVCRM cai antes dos dois). No Power BI: `situacao` com
**Classificar por coluna** em `situacao_ordem`, e em cada gráfico de situação
**Classificar eixo** por `situacao`, crescente (e não pelo total, que põe o
Finalizado em primeiro).

### Sobre o clique: filtra por COLUNA (situação), não por cartão individual

Foi pedido clique que filtre a página igual à tabela de detalhe, mas manter
as 6 colunas sempre visíveis (mesmo com 0 atendimentos, que é o caso de 5 das
6 hoje) e ter clique por CARTÃO individual são **tecnicamente incompatíveis**
neste visual: o HTML Content só cross-filtra quando o campo Granularity tem
uma linha por "coisa clicável", e se essa linha fosse por cartão
(`id_atendimento`), uma coluna sem nenhum atendimento não teria nenhuma linha
pra existir, o visual mostraria só a mensagem genérica de "sem dados" no
lugar, sem cor, sem cabeçalho, sem "0 Registro(s)". Esse caminho foi testado
primeiro e descartado por isso.

A solução foi Granularity por COLUNA: clicar em qualquer lugar de uma coluna
(cabeçalho ou fundo, em qualquer cartão dentro dela) seleciona aquela
situação inteira e filtra o resto da página, inclusive a faixa de KPIs e a
tabela da seção 3. Pra clique por atendimento individual, a tabela de
detalhe da seção 3 já resolve isso.

**Passo a passo pra montar (precisa de duas coisas novas no modelo, não só
colar medida):**

1. **Criar a tabela de apoio:** Modelagem → Nova tabela → cole o conteúdo de
   `Esteira Colunas` (é uma DATATABLE, 6 linhas: situação, tema de cor,
   ordem). Não é medida, não cole como "Nova medida".
2. **Criar o relacionamento:** Modelagem → Gerenciar relacionamentos → Nova:
   `'Esteira Colunas'[situacao]` (lado 1) → `fato_atendimentos_cvcrm[situacao]`
   (lado vários). Direção do filtro: única (padrão).
3. Colar as medidas `Ordem Esteira CVCRM (ordenação)`, `Coluna Esteira CVCRM
   HTML` e `CSS Esteira Atendimentos CVCRM` na pasta `Atendimento CVCRM`,
   igual às outras.
4. Configurar o visual HTML Content:

| Campo | Valor |
|---|---|
| Values | `[Coluna Esteira CVCRM HTML]` |
| Granularity | `'Esteira Colunas'[situacao]` |
| Tooltips | `[Ordem Esteira CVCRM (ordenação)]` |
| Classificar por | Ordem Esteira CVCRM (ordenação), crescente |
| Formatar > Stylesheet > fx | `[CSS Esteira Atendimentos CVCRM]` |
| Formatar > Cross-filtering | Ativar, Transparency 0 |
| Formatar > No data message | (deixe em branco, com a tabela de apoio, o Granularity nunca fica vazio, então essa mensagem nunca aparece) |

## 5. Humor do cliente (pizza) e encerramento no 1º contato

Os dois campos vêm do CVDW (`humor_cliente` e `encerrado_primeiro_contato`, ver
`gold.fato_atendimentos_cvcrm`). Os dois já estavam na bronze, silver e gold
desde a primeira versão, só não tinham sido usados na página.

**Pizza de humor.** Visual nativo (gráfico de pizza), sem HTML.

| Campo | Valor |
|---|---|
| Legenda | `fato_atendimentos_cvcrm[humor_cliente]` |
| Valores | `[Total Atendimentos]` |
| Rótulos de detalhe | Categoria e porcentagem do total |
| Formatar > Fatias > Cores > fx | Formatar por "Valor do campo", campo `[Cor Humor Cliente]` |

A silver decodifica o código do CVCRM em texto (`N` Normal, `I` Irritado, `S`
Satisfeito, vazio "Não informado"). **Só o `N` está confirmado** contra a tela do
CVCRM; `I` e `S` são inferência (ver o comentário em `silver.sql`). Se o dropdown
"Humor do Cliente" do CVCRM tiver outro texto, a correção é nos rótulos do `CASE`
da `silver.atendimentos_cvcrm`, mais nada. Distribuição em 08/out/2026: Normal
297 (90,3%), Irritado 27 (8,2%), Satisfeito 1, Não informado 4. Os 27 irritados
são todos de Atraso de Obra, Distrato e Despesas da Unidade.

Os rótulos só aparecem depois de aplicar a silver no banco e atualizar a tabela
`fato_atendimentos_cvcrm` no Power BI. Antes disso a legenda mostra `N`/`I`/`S`
e todas as fatias saem na cor de fallback (cinza).

**Encerrado no primeiro contato.** Booleano `eh_resolvido_primeiro_contato` na
gold (`S` vira `true`). Em 08/out/2026: 70 de 329, ou 21,3%. A medida
`[Atendimentos Encerrados 1º Contato]` (contagem) e `[Taxa de Resolução 1º Contato]`
(contagem sobre `[Total Atendimentos]`) alimentam o cartão ENCERRADOS 1º CONTATO da
faixa de KPIs (seção 1). Também serve como slicer, usando
`eh_resolvido_primeiro_contato`.

## 6. Gráficos de apoio (visuais nativos)

Todos usam a mesma paleta de humor da pizza: **Legenda** `humor_cliente` e cores
por `fx` > Valor do campo > `[Cor Humor Cliente]`.

**Barras empilhadas por assunto.** Eixo Y `assunto`, Valores `[Total Atendimentos]`,
N principais = 8, dica de ferramenta `[% Clientes Irritados]`. Mostra onde está a
irritação: em 08/out/2026, Distrato tem 11 irritados em 30 (36,7%) e Atraso de
Obra 15 em 107 (14,0%); nenhum outro assunto relevante tem irritado.

**Três gráficos de colunas, uma por equipe** (Atendimento, Contratos e Cobrança,
Repasse). Eixo X `fato_atendimentos_cvcrm[situacao]`, Eixo Y
`[Total Atendimentos]`, sem legenda. Cores por `fx` > Valor do campo >
`[Cor Situação Atendimento CVCRM]` (azul da página em Finalizado, vermelho em
Cancelado, cinza nas demais). O Finalizado **não** usa o verde dos selos da tabela
de detalhe: numa coluna que é 88% a 93% do gráfico, aquele verde saturado ficou
chamativo demais. A separação por equipe é um **filtro no nível
do visual** em `fato_atendimentos_cvcrm[equipe]`, um por gráfico. Ficam de fora
desses três: "Assistência técnica" (5 atendimentos) e os 17 atendimentos sem
equipe preenchida (todos finalizados: Financeiro 8, Comunicados 5, Despesas da
Unidade 4). Em 08/out/2026 as três equipes somam 307 dos 329.

Valores de referência (sem filtro de mês, 08/out/2026):

| Equipe | Total | Finalizado | Cancelado | Em andamento |
|---|---|---|---|---|
| Atendimento | 177 | 165 | 2 | 10 (Time Atendimento 6, Em Atendimento 4) |
| Contratos e Cobrança | 114 | 106 | 5 | 3 (Time Cobrança) |
| Repasse | 16 | 14 | 0 | 2 (Em Atendimento) |

Finalizado concentra de 88% a 93% em cada equipe, então as outras colunas saem
bem baixas ao lado dele; os rótulos de dados é que mostram o valor. Cada gráfico
tem escala própria no eixo Y.

## 7. Tempo para pegar e para atender (14/out/2026)

O gestor comercial pediu três tempos na faixa de KPIs: pegar, atender e finalizar. O CVDW entrega o que é
preciso, no endpoint `atendimentos/workflow/tempo`.

**Correção de uma versão anterior desta seção.** Na manhã de 14/out ela dizia que o CVCRM não
expunha esses marcos. Estava errada. A sondagem de setembro (DP-17) e a primeira de 14/out tentaram
caminhos que não existem (`atendimentos/historico`, `atendimentos/workflow`) e não chegaram em
`atendimentos/workflow/tempo`, que a referência da API lista. A varredura completa da referência
(abaixo) achou o endpoint, e o teste ao vivo confirmou.

### O que o endpoint entrega

`GET /api/v1/cvdw/atendimentos/workflow/tempo`, com e-mail e token, igual ao resto do CVDW. Em
14/out/2026: 1.456 linhas para 445 atendimentos, com 443 atendimentos cobertos (99,6%). Campos:
`idtempo`, `idatendimento`, `idsituacao`, `situacao`, `tempo` e `data_cad`.

Cada linha é uma etapa por onde o atendimento passou. O `tempo` é quanto ele ficou na etapa, em
minutos, e a `data_cad` é o momento em que ele **saiu** dela. Exemplo, o atendimento 429: aberto às
14:39:55, saiu de "Time Atendimento" às 15:10:31 depois de 30 min (alguém pegou) e saiu de "Em
Atendimento" às 15:35:16 depois de 24 min (finalizou). A soma dos `tempo` de um atendimento bate
com `tempo_finalizado` em 396 dos 413 finalizados, com diferença máxima de 4 min (arredondamento).

A situação **atual** de um atendimento em aberto ainda não tem linha: ela só nasce quando o
atendimento sai da etapa. Para o aberto, o tempo na etapa atual é `data_situacao` até agora.

O próprio CVCRM marca qual etapa é "em atendimento": `GET /api/v1/configuracoes/workflows/atendimentos`
devolve flags por situação (`inicio`, `ematendimento`, `fim`, `cancelado`), e `ematendimento = S` só
em "Em Atendimento" (id 12). É a base da definição abaixo.

### Definições

- **Atender** = soma do `tempo` das linhas "Em Atendimento": do momento em que alguém assume até
  finalizar.
- **Pegar** = tudo o que vem antes (Novo Atendimento, Triagem, Time Atendimento, Time Cobrança,
  Time Crédito e as voltas à triagem): da abertura até alguém assumir. É `tempo_finalizado` menos o
  tempo de atender.
- **Finalizar** = `tempo_finalizado`, o cartão que já existe.

Pegar mais atender dá finalizar, sempre. Valem só para atendimentos **finalizados**.

### Números de 14/out/2026 (413 finalizados)

| | Mediana | Média | Média sem os 2 com mais de 30 dias |
|---|---|---|---|
| Pegar | 17 min | 3.893 min | 728 min (12,1 h) |
| Atender | 0 min | 649 min | 543 min (9,1 h) |
| Finalizar | 56 min | 4.541 min | 1.270 min (21,2 h) |

A média total é puxada por um atendimento de fev/2024 que levou 1,3 milhão de minutos (cerca de
909 dias) entre a abertura e a finalização. Por isso o cartão de média precisa vir com a mediana ao
lado, como já foi dito do tempo de finalização.

A mediana de atender é 0 por dois motivos. Em 109 dos 413 finalizados (26%) o atendimento já nasce
finalizado e nunca passa pelo fluxo, então pegar e atender são 0. Nos outros, muitas vezes quem
assume finaliza no mesmo ato (a linha "Em Atendimento" tem 0 min). Isso é o que o CVCRM registra.

Por equipe, mediana de pegar e de atender, em minutos:

| Equipe | Finalizados | Pegar | Atender |
|---|---|---|---|
| Atendimento | 218 | 1 | 4 |
| Contratos e Cobrança | 110 | 119 | 0 |
| Repasse | 18 | 250 | 112 |
| Passou por várias equipes | 39 | 31 | 0 |
| Sem equipe | 26 | 0 | 0 |
| Assistência técnica | 2 | 3.488 | 240 |

### Inventário da varredura (14/out/2026)

Método: o índice do site (`llms.txt` e `sitemap.xml`) lista todas as páginas da referência em
https://desenvolvedor.cvcrm.com.br/reference. Li cada página de atendimento (método, caminho,
parâmetros, campos) e testei ao vivo os GETs, só em leitura, com o e-mail e o token do `.env`. Os
POST e PUT (cadastrar, finalizar, alterar dados, alterar situação, adicionar mensagem, encerrar
tarefa) **não foram chamados**: alteram dados de produção.

| Endpoint | Resultado | O que traz |
|---|---|---|
| `GET /cvdw/atendimentos` | 200, 445 | os 60 campos que a bronze já usa |
| `GET /cvdw/atendimentos/workflow/tempo` | 200, 1.456 | minutos por situação: **pegar e atender** |
| `GET /cvdw/atendimentos/workflow-tempo` | 200, 1.456 | rota antiga do mesmo dado, marcada como "será desativada" |
| `GET /cvdw/atendimentos/respostas` | 200, 246 | mensagens (203 atendimentos, 45,6%); `tempo_resposta` em 8 |
| `GET /cvdw/atendimentos/interacoes` | 200, 37 | 30 atendimentos (6,8%) |
| `GET /cvdw/atendimentos/tarefas` | 200, 12 | 8 atendimentos (1,8%) |
| `GET /cvdw/atendimentos/times` e `/times/integrantes` | 200, 4 e 22 | equipes e membros |
| `GET /relacionamento/atendimentos/listar` | 200 | 51 campos, **com SLA** (ver abaixo) |
| `GET /relacionamento/atendimentos/{id}/mensagens` e `/{idResposta}` | 200 | mensagens com autor e data |
| `GET /relacionamento/atendimentos/tarefas` e `/{idTarefaCriada}` | **405** | a referência diz GET, o servidor só aceita PUT |
| `GET /configuracoes/workflows/atendimentos` | 200 | situações e flags `inicio`, `ematendimento`, `fim`, `cancelado` |
| `GET /configuracoes/workflows/atendimentos/subworkflows` | 200 | só "Workflow padrão" |
| `GET /configuracoes/workflows/atendimentos/{idSituacao}` | 200 | situações para as quais dá para mover |
| `GET /v1/cv/atendimento` | 200, 445 numa página | os mesmos 51 campos do `listar` |
| `GET /v2/cv/indicadores/atendimentos` | 200 | totais do CVCRM, inclusive `sem_interacao` |
| `GET /relacionamento/tarefas-atendimentos` | 200 | tarefas dos atendimentos |
| `GET /cvbot/assuntos-numero/{idNumero}` | 200 | assuntos por número (chatbot) |
| `GET /comercial/leads/atendimentos` | 404 (testado com um id de lead qualquer) | atendimentos de **leads**, domínio de prospecção, não o pós-venda |
| `GET /v1/cv/bi/atendimento_n1n2` e as seis rotas filhas (`tempo_medio`, `sla_n1`, `sla_n2`, `percentual_n1`, `responsaveis`, `total_finalizados`) | 401 | só com token Bearer |
| `GET /v1/comunicador/metricas/tempo-medio-atendimentos` | 401 | só com token Bearer |
| `GET /v4/relacionamento/tipos-atendimentos` | 401 | só com token Bearer |
| `GET /v1/cliente/atendimentos/situacoes` | 401 | token JWT do cliente |

Fora do alcance: as rotas de BI N1/N2 (SLA por nível e tempo médio), do comunicador e de tipos exigem
login com token Bearer. A referência diz que ficam disponíveis só na rede interna do CV, mas isso
não bateu com o teste: `v1/cv/atendimento` e `v2/cv/indicadores/atendimentos` diziam o mesmo e
responderam 200 com e-mail e token.

### Outros achados úteis

- **SLA existe na API.** `relacionamento/atendimentos/listar` e `v1/cv/atendimento` devolvem
  `slaAssunto` (em horas: 24, 48, 72, conferido porque `dataVencimentoAssunto` é a abertura mais
  esse tanto de horas), `dataVencimentoAssunto`, `slaSubassunto`, `slaWorkflow` e
  `dataVencimentoWorkflow`. O CVDW não traz esses campos, e foi por isso que a esteira (seção 4)
  ficou sem as linhas de "vencimento de SLA". Agora dá para incluí-las.
- **Horário errado em um campo.** `dataUltimaModificacaoSituacao` do `listar` vem 2 h adiantado
  em relação à `data_situacao` do CVDW (11:32:25 contra 09:32:25 no atendimento 290). Use a do CVDW.
- **O indicador do próprio CVCRM confirma o achado de interações:** `sem_interacao` é 437 de 445.
  Quase nenhum atendimento tem interação registrada, e por isso `interacoes` e `tempo_resposta` não
  servem para medir pegar. O `workflow/tempo` sim.

### O que foi construído (14/out/2026)

- **Ingestão.** Objeto `atendimentos_workflow_tempo` em `config/objetos.yml` (chave `idtempo`, modo
  incremental normal), tabelas `bronze.atendimentos_workflow_tempo` e `_snapshot` em `bronze.sql`.
  Carga completa de 1.456 registros feita da máquina do dev pelo túnel, e o modo incremental foi
  testado (buscou 248 registros desde 13/10 e fez upsert sem duplicar).
- **Silver.** `silver.atendimentos_workflow_tempo`, uma linha por etapa, com `tempo_min`,
  `data_saida` e `eh_em_atendimento`.
- **Gold.** `gold.fato_atendimentos_cvcrm` ganhou `tempo_pegar_min` e `tempo_atender_min`, só para
  finalizados. Validação no banco: 411 finalizados, todos com os dois valores, nenhum aberto com
  valor, nenhum negativo, e `pegar + atender = tempo_finalizado` em todos os 411. Medianas no banco:
  pegar 17 min, atender 0 min, finalizar 57 min.
- **Medidas e cartões** no `MEDIDAS_ATENDIMENTO_CVCRM.dax` (seção 1).

**Para as colunas aparecerem no Power BI** vale o mesmo passo de sempre: Transformar dados, a consulta
`fato_atendimentos_cvcrm`, Atualizar visualização, Fechar e aplicar. Feito em 15/out/2026, e as medidas
e a faixa de sete cartões já estão no modelo.

**Valores de referência (modelo de 15/out/2026, 411 finalizados).** Os cartões mostram a mediana:
sem filtro de período, pegar 17 min, atender 0 min e finalizar 57 min. As médias, que não aparecem
mais na faixa mas seguem no modelo, são pegar 65,2 h, atender 10,9 h e finalizar 76,1 h, infladas
pelo atendimento de fev/2024, e nelas pegar + atender fecha exatamente com finalizar. Por mês de
abertura (o que o cartão mostra com o mês filtrado é a primeira coluna de cada par):

| Mês | Finalizados | Pegar (mediana, média) | Atender (mediana, média) | Finalizar (mediana, média) |
|---|---|---|---|---|
| set/2026 | 195 | 18 min, 12,4 h | 0 min, 15,3 h | 65 min, 27,8 h |
| out/2026 | 214 | 15 min, 11,9 h | 0 min, 3,4 h | 45 min, 15,4 h |

### O que fica para o deploy na VM

A produção já tem tudo (tabelas, carga e views), então o Power BI já enxerga os dados. Falta a VM
receber os arquivos para a carga horária continuar alimentando o objeto novo:
`config/objetos.yml`, `sql/bronze/bronze.sql`, `sql/silver/silver.sql`, `sql/gold/gold.sql` e
`aplicar_silver.py`, na branch que a VM usa. Sem isso a carga horária não busca as etapas novas, e os
atendimentos finalizados daí em diante ficam **sem** tempo de pegar e de atender (as colunas ficam
vazias, e a média e a mediana só enxergam o que já foi carregado). O tempo de finalização não é
afetado.

A view nova da silver e as colunas novas da gold usam `CREATE OR REPLACE`, sem DROP delas. Rode
`aplicar_silver.py` e `aplicar_gold.py` na VM como `pafil_app` (o dono das views): rodar como
`postgres` e recriar uma view por DROP deixaria o dono errado e o `pafil_bi` sem leitura. O
`gold.sql` tem DROP CASCADE de outras views (por exemplo `fato_reservas`), que já era assim.

## Pendências conhecidas

- `id_corretor`/`corretor` vinham vazios nos 10 registros da primeira versão,
  sem relacionamento com `dim_corretor` por ora (ver nota no `gold.sql`).
  Reconferir agora que são 329 e ligar se o campo passou a vir preenchido.
- Unidade de `tempo_finalizado`: **minutos**, confirmada em 08/out/2026 (ver
  seção 1). `tempo_resposta` tem só 3 registros preenchidos em 329; a unidade
  foi assumida igual (minutos), sem como provar.
- Rótulos `Irritado` e `Satisfeito` do humor: inferidos, não confirmados contra
  o dropdown do CVCRM (seção 5).
- `origem` (2 letras) e `canal` (Telefone/Email/Whatsapp) ainda não têm
  de-para nem página de referência, expostos crus, prontos pra virar slicer
  quando fizer sentido de negócio.
