# Página "Atendimento" (Blip)

Réplica das telas do painel nativo do Blip, sobre `gold.fato_atendimentos`. As
medidas estão em [MEDIDAS_ATENDIMENTO.dax](MEDIDAS_ATENDIMENTO.dax).

A página existe por dois motivos. O primeiro é tirar a gestão de dentro do
painel do Blip, que ninguém acompanha porque vive em outra ferramenta. O
segundo é o que o painel nativo não faz: cruzar atendimento com empreendimento,
e no futuro com venda e lead, já que as dimensões são as mesmas do resto do
modelo.

## Antes de montar

Confirme que a `dim_calendario` cobre o mês corrente. Se ela terminar antes, os
relacionamentos de data continuam existindo, o Power BI não reclama de nada, e
todo visual por dia vem vazio. É o erro mais caro de diagnosticar aqui.

## Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  1. Faixa de KPIs (HTML Content)                                     │
├────────────────────────────────────┬─────────────────────────────────┤
│  2. Criados x Fechados por dia     │  3. Tickets por situação        │
│     (gráfico de linhas)            │     (barras horizontais)        │
├────────────────────────────────────┴─────────────────────────────────┤
│  4. Tabelas de corte (HTML): atendente, fila, empreendimento         │
├──────────────────────────────────────────────────────────────────────┤
│  5. Rodapé de qualidade do dado (dois cartões pequenos)              │
└──────────────────────────────────────────────────────────────────────┘
```

## 1. Faixa de KPIs

**Visual:** HTML Content (o mesmo já usado nas outras páginas).
**Medida:** `[KPIs Atendimento HTML]`.

Nove cartões, no mesmo CSS da faixa de Performance. As cores não são
decorativas: o par vermelho é o de abandono, que é a métrica que dói, e o cinza
é o único cartão que mostra uma foto do momento em vez de uma medida do
período.

Dois cuidados de leitura, que valem explicar para quem for usar a página:

- "TOTAL" e "FINALIZADOS" olham datas diferentes. TOTAL é o que entrou no
  período (`[Tickets Criados]`, data de criação); FINALIZADOS é o que saiu
  (`[Tickets Finalizados (padrão Blip)]`, data de fechamento, e inclui o
  transferido, igual ao painel nativo). É a mesma leitura do gráfico de Criados
  x Fechados, em número: total acima de finalizados quer dizer fila crescendo.
  Com um mês selecionado os dois não fecham por soma com "EM ABERTO", e não é
  para fechar.
- "ABANDONADOS" está dentro de "FINALIZADOS", não ao lado. A definição padrão
  Blip inclui o encerrado por inatividade, que é o abandonado da silver. Sem
  filtro de mês, FINALIZADOS + EM ABERTO = TOTAL; somar ABANDONADOS por cima
  conta os mesmos tickets duas vezes. O subtítulo do cartão ("dos finalizados,
  cliente parou de responder") existe para deixar isso explícito na tela.
- "EM ABERTO" é o único que não pertence a mês nenhum. Filtrar a página para
  "agosto" muda os oito cartões e **não** muda esse, porque a medida tira o
  filtro do calendário de propósito (`REMOVEFILTERS ( dim_calendario )`). Sem
  isso o cartão zerava ao escolher um mês, já que ticket em aberto não tem data
  de fechamento. E ele conta só `Open` e `Waiting`: transferido não está na fila,
  para o Blip ele já terminou do lado de quem transferiu.

## 2. Criados x Fechados por dia

**Visual:** Gráfico de linhas.
**Eixo X:** `dim_calendario[data]`.
**Valores:** `[Tickets Criados]` e `[Tickets Fechados]`.

Linha, e não coluna, porque a leitura aqui é de ritmo ao longo do tempo, não de
comparação entre categorias. As duas séries juntas mostram se a operação está
dando conta: quando a linha de criados fica sistematicamente acima da de
fechados, a fila está crescendo.

`[Tickets Criados]` usa `USERELATIONSHIP` para passar pela data de criação, já
que o relacionamento ativo é o de fechamento. Isso já está dentro da medida,
não precisa fazer nada no visual.

## 3. Tickets por situação

**Visual:** Gráfico de barras empilhadas horizontal.
**Eixo Y:** `fato_atendimentos[situacao]`.
**Valores:** contagem de `sequential_id`.

Barra horizontal em vez de rosca porque são seis categorias com nomes longos, e
rosca com seis fatias vira legenda ilegível. Se a gestão preferir a leitura de
proporção, troque para barras 100% empilhadas em vez de rosca.

## 4. As tabelas de corte

São as três abas do painel (Atendentes, Filas, Tags). Há dois caminhos, e eles
resolvem problemas diferentes.

### Caminho principal: as tabelas em HTML, com clique que filtra a página

**Visual:** HTML Content, um para cada tabela.
**Medidas:** `[Linha Atendente HTML]`, `[Linha Fila HTML]`,
`[Linha Empreendimento HTML]`, `[Linha Motivo HTML]`, `[Linha Tag HTML]`.

Uma tabela montada por uma medida só (as `[Tabela ... HTML]`, que continuam no
arquivo) é um texto para o Power BI: clicar numa linha não filtra nada. Para o
clique funcionar, o visual precisa de contexto de linha, e isso muda o desenho:
a medida devolve **uma linha por registro**, e o visual monta a lista. A partir
daí clique filtra o resto da página, Ctrl+clique acumula seleção e clique direito
abre o menu de drillthrough. Precisa do HTML Content 1.4.0 ou mais novo (se veio
do AppSource, já é).

Montagem de cada visual, na ordem:

1. **Values:** a medida `[Linha ... HTML]`.
2. **Granularity:** a coluna da linha (`dim_atendente[atendente]`,
   `dim_fila[fila_exibicao]`, `dim_empreendimento[empreendimento]`,
   `fato_atendimentos[motivo_encerramento]` ou `fato_atendimentos[tag]`).
3. **Tooltips:** `[Tickets Finalizados (padrão Blip)]`. Não é pelo tooltip, é
   para a medida aparecer em "Classificar por".
4. **Classificar por** essa medida, decrescente. Sem isso a tabela vem em ordem
   alfabética.
5. **Formatar > Stylesheet > fx** e apontar para `[CSS Tabela Atendimento (linhas)]`.
6. **Formatar > Cross-filtering:** ativar, e Transparency em 0. O CSS já apaga
   quem não está selecionado (classe `unselected`), e a transparência do visual
   não teria efeito nesse layout de qualquer forma.
7. **Formatar > No data message:** "Nenhum atendimento no período selecionado."
   Sem linhas nenhuma medida roda, então a mensagem tem que vir do visual.
8. Nas tabelas de empreendimento, motivo e tag: **filtro de visual "não está em
   branco"** na coluna de Granularity. A medida já esconde essa linha, mas só o
   filtro tira ela do dataset, e se ela ficasse lá vazia poderia levar o
   cabeçalho junto.

Se quiser conferir a estrutura que o visual gera, ligue "Show raw HTML" nas
opções de formatação: cada linha vem dentro de um `<div class="htmlViewerEntry">`.

O CSS é compartilhado entre as cinco, então ajuste de estilo entra num lugar
só. Três coisas que a tabela HTML entrega e a matriz nativa não:

- **Ordenação por quantidade que funciona de verdade**, porque é sobre o
  número. Na matriz nativa, ordenar por uma coluna de tempo cai no texto
  formatado e coloca `09:00:00` depois de `10:00:00`.
- **Barra de volume atrás da quantidade**, proporcional ao maior da tabela
  dentro do recorte atual (mês, fila clicada na outra tabela).
- **Cabeçalho fixo ao rolar**, e largura de coluna que não depende de ninguém
  arrastar nada.

Um detalhe de implementação que vale registrar, porque custou duas versões
quebradas do CSS: o visual põe um `<div>` sem classe dentro de cada
`.htmlViewerEntry` (está no código-fonte, não na documentação). O CSS dissolve
os dois com `display:contents` para as células caírem numa grade única. Se a
tabela um dia voltar a aparecer com as células empilhadas, é essa estrutura que
mudou; "Show raw HTML" mostra como ela está.

Para reproduzir as abas do painel, coloque as tabelas no mesmo lugar da página
e troque com indicadores (bookmarks) mais um navegador de indicadores.

### Caminho alternativo: matriz nativa com parâmetro de campo

**Visual:** Matriz.
**Linhas:** a coluna de campos de `Seleção Corte Atendimento`.
**Slicer:** a coluna de texto do mesmo parâmetro.
**Valores:** `[Tickets Finalizados]`, `[Tempo Médio 1a Resposta]`,
`[Tempo Médio Espera Fila]`, `[Tempo Médio Resposta]`, `[Tempo Médio Atendimento]`.

Um visual só, com um slicer trocando a dimensão da linha, e sem indicador
nenhum para manter. Vale quando você quiser exportar os dados pelo menu do
visual ou fixar o visual num painel do Serviço, que a tabela HTML não permite.

Aqui a limitação da ordenação se aplica: deixe ordenando por
`[Tickets Finalizados]`, e se precisar ordenar por um tempo, acrescente a
medida `(seg)` correspondente ao visual.

## 5. Rodapé de qualidade do dado

**Visual:** dois cartões.
**Medidas:** `[% Tickets com Empreendimento]` e `[% Tickets sem Tag de Empreendimento]`.

Parecem detalhe e não são. O corte por empreendimento falha por omissão: ticket
cuja tag não casa com a de-para some do visual filtrado por produto, sem erro e
sem aviso. Estes dois cartões são a única coisa que denuncia isso.

As duas medem coisas diferentes. A segunda é atendente que não marcou a tag (na
base de setembro, 42% dos fechados). A primeira, quando fica abaixo do
complemento da segunda, é grafia do Blip que falta na de-para de
empreendimentos, e a correção é na planilha do backoffice, não no SQL. A view
`gold.blip_tags_sem_empreendimento` lista exatamente quais faltam.

## 6. Tabelona de tickets (página própria)

**Visual:** HTML Content, numa página separada chamada "Atendimento (dados)".
**Medida:** `[Linha Ticket HTML]`, com `[CSS Tabela Tickets (linhas)]` no Stylesheet.
**Grão:** um ticket por linha, dezesseis colunas.

É o mesmo desenho das tabelas com clique da seção 4, no grão do ticket. Existe
para o usuário levar tudo de uma vez: **três pontinhos do visual > Exportar
dados > Dados resumidos** sai com uma linha por ticket e as colunas que estão
em Granularity e em Tooltips. A coluna com o HTML da medida vai junto; é só
apagar no Excel.

**O limite que importa:** o HTML Content pede ao Power BI no máximo **1.000
linhas** e não pagina. Acima disso ele mostra as 1.000 primeiras na ordem
escolhida, sem avisar. Com o filtro de mês ligado a base fica em algumas
centenas e cabe; a base inteira do Blip já passa de 1.300 e não cabe. A legenda
de rodapé da tabela diz isso na tela, e os slicers desta página devem ser os
mesmos da principal, sincronizados (Exibição > Sincronizar segmentações), para
o que o gestor filtrou lá ser o que ele exporta aqui.

Montagem:

1. **Values:** `[Linha Ticket HTML]`.
2. **Granularity:** `fato_atendimentos[sequential_id]` primeiro (é o grão; a
   medida só depende dele). Depois, para saírem na exportação:
   `parent_sequential_id`, `data_criacao`, `data_abertura`, `data_fechamento`,
   `situacao`, `dim_atendente[atendente]`, `dim_fila[fila_exibicao]`, `canal`,
   `dim_empreendimento[empreendimento]`, `motivo_encerramento`, `tag`. Nas
   datas, escolha a coluna e não a hierarquia.
3. **Tooltips:** `[Tempo Médio Espera Fila]`, `[Tempo Médio 1a Resposta]`,
   `[Tempo Médio Resposta]`, `[Tempo Médio Atendimento]`. No grão do ticket a
   média de uma linha é o próprio valor, e assim os tempos saem na exportação.
   Se alguém for fazer conta em Excel, acrescente também as medidas `(seg)`:
   texto "01:09:12" o Excel às vezes converte, às vezes não.
4. **Classificar por** `sequential_id`, decrescente (mais novo em cima).
5. **Formatar > Stylesheet > fx** > `[CSS Tabela Tickets (linhas)]`. É o CSS
   das outras tabelas com dezesseis colunas, mesma fonte e mesmos tamanhos,
   derivado da medida base por `SUBSTITUTE`, então ajuste de estilo feito lá
   chega aqui. Com dezesseis colunas nesse tamanho a tabela rola na horizontal;
   é esperado.
6. **Cross-filtering** ativo, Transparency 0; **No data message** "Nenhum
   ticket no período selecionado."

Na exportação, o Desktop gera .csv e o Serviço .xlsx ou .csv.

## 7. Tickets por hora do dia (colunas + linha)

**Visual:** Gráfico de colunas e linhas agrupadas.
**Eixo X:** `fato_atendimentos[hora_criacao]` (0 a 23, tipo Categórico).
**Eixo Y das colunas:** `[Tickets Criados]`.
**Eixo Y da linha:** `[Espera Mediana Fila (min)]` (eixo secundário).

Responde duas perguntas no mesmo gráfico: a que horas a demanda chega (colunas) e
se a fila está dando conta nessa hora (linha). A hora vem da **criação** do
ticket (`storage_date`), que é quando o cliente entra, e não da abertura, que é
quando o atendente pega.

`hora_criacao` é coluna da gold (`blip.sql`, no fim da `gold.fato_atendimentos`),
calculada com `AT TIME ZONE 'America/Sao_Paulo'`. Não calcule a hora no DAX com
`HOUR(storage_date)`: o Desktop converte `timestamptz` para o fuso da máquina e o
Serviço/gateway não, então no notebook sai certo e depois de publicar sai três
horas adiantado. Para a coluna aparecer no modelo, o botão Atualizar **não basta**:
ele recarrega os dados das colunas que o modelo já conhece e deixa a nova de fora
(conferido em 08/out/2026, mesmo a consulta sendo só uma navegação). Faça
**Transformar dados**, selecione a consulta `fato_atendimentos_blip`, **Atualizar
visualização** e **Fechar e aplicar**.

**Mediana, não média, na linha.** A espera média por hora engana: às 17h a média
da base é 306 min e a mediana é 8 min, porque ticket que entra perto do fim do
expediente fica na fila até o dia seguinte e puxa a média. Mesmo caso das 16h
(média 168, mediana 4). As 12h são diferentes: lá a média (107) e a mediana (63)
sobem juntas, ou seja, a espera é alta para quase todo mundo daquela hora
(provavelmente o horário de almoço da equipe, a confirmar com a gestão).
`[Tempo Médio Espera Fila]` continua certa para o cartão, que replica o painel do
Blip; para comparar horas, use a mediana.

**Filtro no visual:** `hora_criacao` entre 7 e 18. Na base, os tickets se
concentram das 8h às 17h, e só 9 de 2.378 (0,4%) entram fora de 7h a 18h (0h, 1h,
3h, 19h e 20h, de 1 a 4 tickets cada). A mediana de espera desses poucos é de 7 a
13 horas, e se ficarem no eixo esmagam a linha das horas úteis (2 a 110 min). Diga
isso no rodapé do gráfico: ele não mostra 100% dos tickets.

Valores de referência (base inteira, 08/out/2026): pico às 10h (342 tickets),
seguido de 11h (282) e 9h (272); queda às 12h (176, abaixo de 11h e de 13h), quando
a mediana de espera sobe a 62 min. Das 8h às 17h a mediana fica entre 4 e 15 min,
exceto às 12h.

## 8. Tickets por fila (pizza)

**Visual:** Gráfico de pizza.
**Legenda:** `dim_fila[fila_exibicao]`. **Valores:** `[Tickets Criados]`.
**Filtro no visual:** `fila_exibicao`, N principais = 6 pelo `[Tickets Criados]`.

Usa `[Tickets Criados]` (a entrada) para bater com o cartão TOTAL da faixa, e não
`[Tickets Finalizados (padrão Blip)]`, que alimenta a tabela de filas. Os números
diferem em poucos tickets (694 contra 692 na fila de 2ª via, por exemplo).

Base inteira em 08/out/2026, 8 filas com ticket: Transferência direta 1.035
(44,5%), 2ª via de boleto 694 (29,9%), Default 182 (7,8%), Relacionamento com
cliente 174 (7,5%), Renegociação de Parcelas e Contratos 170 (7,3%), Financiamento
66 (2,8%), Assistência Técnica 2 e Crédito e Repasse 1. As duas últimas somem com o
N principais = 6; sem ele viram fatias invisíveis. Outras cinco filas (Contas a
Receber, Campanhas, Falar com atendente, Fila_Teste e Fila_TesteVini) existem no
cadastro e não têm ticket, então a pizza as ignora sozinha.

**O que a pizza não conta sozinha.** "Transferência direta" é o nome de exibição da
fila técnica `DIRECT_TRANSFER`, que não existe no cadastro de filas do Blip
(`/teams`) e aparece só nos tickets; é a maior fatia (44,5%). Não é uma fila de
negócio, então a pizza mistura "por onde o ticket entrou" com "o que o cliente
queria". "Default" (7,8%) é o nome genérico da fila padrão do Blip; vale confirmar
com quem administra o Blip se ela tem uso de negócio. Não conferi o que cada uma
dessas duas significa na operação. Se a gestão quiser a distribuição só das filas
de negócio, a tabela de filas (seção 4), com barra de volume e clique, serve melhor
que a pizza.

Cores sugeridas (rampa do azul da página, da maior fatia para a menor; fixe uma
por fila em Formatar > Fatias > Cores, senão a cor muda quando o filtro muda):
Transferência direta `#003254`, 2ª via de boleto `#2E5E82`, Default `#5F8AAA`,
Relacionamento com cliente `#8FB0C8`, Renegociação `#BCD0DF`, Financiamento
`#6B7280`.

## Slicers da página

`dim_calendario[data]` como intervalo, mais `dim_fila[fila_exibicao]`,
`dim_atendente[atendente]` e `fato_atendimentos[canal]`.

Vale acrescentar `dim_fila[cadastrada_no_blip]` e
`dim_atendente[cadastrado_no_blip]` como slicers escondidos de diagnóstico. Elas
marcam a fila ou o atendente que aparece nos tickets mas não no cadastro do
Blip, que é o caso da fila `DIRECT_TRANSFER` e de qualquer atendente desligado.

## O que não está aqui, e por quê

Duas telas do painel ficaram de fora por falta de fonte, não por decisão de
layout.

**Atingimento SLA.** A regra está configurada dentro do Blip e não é exposta por
nenhum endpoint da API. Assim que alguém informar qual é (tempo até primeira
resposta, qual limite, se varia por fila), ela vira uma medida calculada sobre
`ate_primeira_resposta_seg` e entra na matriz como mais uma coluna.

**Disponibilidade de atendentes.** O painel mostra tempo acumulado por estado
(Online, Em pausa, Invisível). A API só devolve o estado do instante, e não há
recurso de histórico, então não dá para reconstruir o passado. Exigiria um
coletor próprio de alta frequência, e ele só produziria dados daqui para frente.

## Conferência antes de publicar

Filtre a página numa janela fechada e compare com o painel do Blip na mesma
janela, cartão a cartão. Para 3 a 9 de setembro de 2026 os números do painel
eram 353 fechados, 341 finalizados, 12 abandonados, e os tempos 01:09:12,
00:11:12, 01:29:28, 01:11:06 e 10:23:43.

Uma diferença de forma que não é erro: acima de 24 horas o painel escreve
`1d 10:18` e as medidas daqui escrevem `34:18:00`. A escolha foi proposital,
porque valor monotônico ordena certo numa tabela e `1d 10:18` não.

Duas diferenças de conteúdo que também não são erro, e que já custaram uma
investigação inteira em 10 de setembro de 2026:

A primeira é o período. Comparar as duas telas sem travar a mesma janela nas duas
não diz nada: foi assim que uma comparação apontou 499 contra 900 quando o
dashboard estava em agosto e o painel avançava por setembro.

A segunda é o que cada tela chama de finalizado. O painel conta o ticket
transferido como finalizado na fila e no atendente de origem, e nós não. São 27
por cento da base, então a diferença é grande. Para conferir contra o painel, use
`[Tickets Finalizados (padrão Blip)]`, que existe só para isso. O levantamento
completo, com as outras três causas encontradas, está em
`reconciliacao/blip_painel_vs_dashboard.md`.
