# Performance: como replicar a página do legado (farol e visão por mês)

Este documento é o mapa visual a visual da página "Performance" do BI Matriz
legado, no mesmo espírito do `PAGINA_PRECO.md` e do `PAGINA_PERFIL_CLIENTE.md`.
Foi extraído dos `visualContainers` de `_bi_ref/matriz_report.json` (a página se
chama `f9e56b50357dc9d1579a`, com 6 visuais) e do `matriz_model.bim`, de onde
saíram as fórmulas originais das medidas.

As medidas ficam em [`powerbi/MEDIDAS_PERFORMANCE.dax`](MEDIDAS_PERFORMANCE.dax).
A montagem em si, como o resto do `.pbix`, é manual no Power BI Desktop.

---

## 1. Como a página é no legado

São 6 visuais, sendo 2 de dado:

| Visual | Tipo | Linhas | Colunas | Valores |
|---|---|---|---|---|
| Corretores | matriz | `f_headcount.Nome` e o nível Mês da hierarquia de datas | | Qtd Prospect, Qtd Ativo, Ativo/Mês, Qtd Receptivo, Receptivo/Mês, Qtd Pastas, Lead/Pasta, Pasta/Mês, Qtd Vendas 2, Pasta/Venda, Vendas/Mes, Soma de Valor do contrato, **Farol Vendas** |
| Vendas x Gerentes | matriz | `dpara_gerentes.Gerente Responsável` e `f_reservas.Corretor` | `d_calendario.Nome do Mês` | QUANTIDADE VENDAS, VGV Bruto |
| Cards do topo | cartão novo | | | Qtd Prospect, Qtd Leads, Qtd Pastas, Taxa de Pasta/Apto, Qtd Vendas 2, Pasta/Venda |
| Legenda do farol | caixa de texto | | | texto fixo com as quatro cores |
| Slicer DATA | segmentação | hierarquia Ano, Mês, Dia de `d_calendario` | | |
| Logotipo | imagem | | | |

Os filtros fixos da matriz de gerentes, no nível do visual, são quatro:
`f_reservas.Situação` em `{Vendida, Distrato}`, `dpara_gerentes.Share` igual a
"House RPO", `f_reservas.Imobiliária` igual a "ESPACO DE NEGOCIOS PAFIL RIBEIRAO
PRETO" e a exclusão de uma corretora específica (Regiane Aparecida da Silva
Padilha, que é coordenação, não venda). Na v3 esses três primeiros já saem da
classificação oficial e dos atributos da dimensão, e a exclusão de coordenação
vira filtro por `silver.dpara_corretor_fora_ranking`, como no resto do projeto.

Vale dizer o que a página do legado **não** tem, para não perder tempo
procurando: ela não tem cards de conversão prontos por corretor, não tem
ordenação por farol e não tem nenhuma medida de "meses sem vender". Esses três
são acréscimos da v3.

---

## 2. A peça que faltava: meses ativos (DP-16)

O farol e as medidas terminadas em "/Mês" dependem todos do mesmo insumo, que é
o único pedaço da página que não existia na pipeline: quantos meses cada corretor
esteve ativo.

No legado isso vinha da planilha de headcount do backoffice (a mesma do DP-12,
`HeadCount/Base Corretores Pafil 22-23.xlsx`, aba "Base Pafil"), que tem uma
coluna por mês, de janeiro de 2022 a dezembro de 2026, preenchida com 0 ou 1, e
duas colunas de resumo, "Meses Ativos 2024" e "Meses Ativos 2025". As medidas
somavam essas duas colunas, com os anos fixos no código DAX. Isso funcionou até
2025 e envelheceu mal: em 2026 o denominador parou de crescer.

Na v3 a matriz mensal inteira virou dado, no grão de corretor por mês:

- `silver.dpara_corretor_headcount_mensal` (a tabela seed, DP-16), carregada por
  `popular_seeds.py` a partir da mesma planilha do DP-12, na mesma passada;
- `gold.fato_headcount_mensal` (a view consumida pelo Power BI), com
  `corretor_chave`, `mes`, `ano_mes` e a flag `ativo`.

Quem escolhe a janela agora é a medida, respeitando o filtro de período da
página, em vez de dois anos escritos no código.

### 2.1 A validação

O despivotamento foi conferido contra as próprias colunas de resumo da planilha:
para os 258 corretores da base, a soma dos meses de 2024 calculada pelo loader
bate exatamente com "Meses Ativos 2024", e o mesmo vale para 2025. Zero
divergências dos dois lados.

### 2.2 A pegadinha do mês corrente

A planilha é preenchida à mão pelo backoffice e costuma atrasar. Em 9 de setembro
de 2026, por exemplo, a coluna de setembro estava zerada para todo mundo, embora
15 corretores estivessem trabalhando normalmente. Se o loader copiasse a planilha
ao pé da letra, o denominador do mês em curso seria zero e todas as medidas por
mês apareceriam vazias justamente no mês que o gestor está olhando.

Por isso a tabela guarda três colunas e não uma:

| Coluna | O que é |
|---|---|
| `ativo_planilha` | o 0 ou 1 exatamente como está na célula |
| `ativo_contrato` | derivado de "Dt contratação" e "Dt desligamento", que estão sempre em dia |
| `ativo` | o efetivo, usado pelas medidas |

A regra do efetivo é simples: a planilha manda até o último mês que ela realmente
preencheu, e dali até o mês corrente vale o contrato. Mês futuro nunca conta.
As duas colunas de auditoria ficam expostas na view de propósito, para conferir a
qualquer momento de onde veio cada número.

### 2.3 As datas de entrada e saída (10 de setembro de 2026)

A série mensal resolve o denominador, mas ela é um proxy ruim para a outra pergunta
do farol: "essa pessoa acabou de chegar?". Somar meses ativos não distingue quem
entrou no mês passado de quem esteve fora da folha por dois meses no meio do ano, e
some com o corretor que entrou e saiu antes do período filtrado.

Por isso o headcount do DP-12, que já era a fonte da equipe, passou a carregar
também `Dt contratação` e `Dt desligamento`, no grão de uma linha por corretor.
`gold.dim_corretor_headcount` expõe as duas como `dt_contratacao` e `dt_desligamento`,
mais uma coluna de conveniência, `meses_de_casa`.

Na mesma passada, o DP-12 deixou de carregar só os ativos e passou a trazer o quadro
inteiro, 258 nomes, com a coluna `eh_ativo` separando quem é quem. Isso está contado
em detalhe na seção 5, porque era um furo de verdade na página: as linhas da matriz
vêm dessa dimensão, e quem saía no meio do ano perdia a linha enquanto as vendas dele
continuavam no Total.

Três coisas valem saber sobre essas colunas:

**A data de entrada é a do vínculo corrente.** Corretor recontratado tem mais de uma
linha na planilha, e o que fica aqui é a volta. O caso real hoje é Beatriz Eburneo de
Barros: entrou em fevereiro de 2024, saiu em outubro de 2024 e voltou em fevereiro de
2025, então para o farol ela tem 19 meses de casa em setembro de 2026, e não 31. A
passagem antiga não se perde, continua na série do DP-16, que despivota linha a linha.

**A data de saída manda no farol, e a flag não.** O que a medida pergunta é se a
pessoa já tinha saído na data de referência da página, e não se ela está ativa hoje.
A diferença aparece quando o gestor olha janeiro: quem saiu em agosto ainda estava na
casa em janeiro e continua sendo cobrado por venda naquele mês, que é o comportamento
que se espera de uma foto do passado.

**Corretor ativo com data de saída lançada também fica branco.** É a janela em que o
backoffice registrou a saída mas ainda não virou o status, e é exatamente quando o
farol erraria mais feio, cobrando venda de alguém que já está de saída.

---

## 3. Passo a passo da montagem

1. **Aplique o SQL** (a tabela seed e a view nova):

   ```
   python aplicar_silver.py
   python aplicar_gold.py
   ```

2. **Carregue a série mensal.** O `.env` já aponta para a planilha do OneDrive na
   variável `HEADCOUNT_CORRETORES_XLSX`, então basta:

   ```
   python popular_seeds.py
   ```

   O log deve terminar com uma linha assim, dizendo até quando a planilha estava
   preenchida:

   ```
   silver.dpara_corretor_headcount_mensal <- 15480 linhas (258 corretores x 60 meses,
   1671 meses-corretor ativos; planilha preenchida até 08/2026)
   ```

   Isso já entra no `atualizar.ps1` de rotina, junto do DP-12: as duas cargas
   leem a mesma planilha na mesma passada.

3. **Importe a tabela nova no Desktop**, por Obter dados, PostgreSQL, schema
   `gold`, tabela `fato_headcount_mensal`. Tem que ser pela interface: criar
   tabela por XMLA num `.pbix` aberto quebra o salvamento do arquivo (a lição
   cara de 12 de agosto de 2026, registrada em `docs/modelo-semantico.md`).

   **E traga as colunas novas de `dim_corretor_headcount`.** Se essa tabela já
   estava no seu modelo antes de 10 de setembro de 2026, um Atualizar não vai
   trazer `eh_ativo`, `dt_contratacao`, `dt_desligamento` e `meses_de_casa` sozinho:
   abra o Editor do Power Query, entre na consulta `dim_corretor_headcount` e marque
   as quatro na etapa de seleção de colunas antes de atualizar. É a mesma pegadinha
   que segurou `documento_chave` e `valor_prestacao` em `fato_precadastros` por
   semanas. Sem essas colunas, `[Meses de Casa]` volta vazia e o farol cai no plano B,
   que é a série mensal do DP-16.

   Repare que a tabela vai crescer de 14 para 258 linhas nesse mesmo refresh, porque
   agora ela carrega o quadro inteiro. Isso é esperado, e a matriz continua mostrando
   só quem teve movimento (veja a seção 5).

4. **Crie um relacionamento só**, de `dim_corretor_headcount[corretor_chave]`
   para `fato_headcount_mensal[corretor_chave]`, de um para muitos, direção
   simples.

   Não crie relacionamento com `dim_calendario`. A ponte de tempo é feita por
   `TREATAS` dentro da medida `[Meses Ativos]`, e isso é deliberado por dois
   motivos: um relacionamento físico com `mes` só pegaria quando o dia 1 do mês
   estivesse selecionado (um slicer de 10 a 20 de setembro zeraria o
   denominador), e ainda abriria um caminho ambíguo com as três fatos.

5. **Cole as medidas** de `MEDIDAS_PERFORMANCE.dax` na tabela de medidas, dentro
   de uma pasta de exibição "Performance". Se `Qtd Ativo` e `Qtd Receptivo` já
   existirem no seu modelo, pule as duas e só confira a fórmula.

6. **Monte a matriz de corretores** (visual Matriz):

   - Linhas: `dim_corretor_headcount[corretor]` e, abaixo dele,
     `dim_calendario[mes_abrev]`. É esse segundo nível que dá a visão por mês:
     o gestor expande o corretor e vê o ano dele mês a mês. Ative
     "Ativar/desativar linhas em camadas" se quiser o formato compacto do
     legado, e confirme que `mes_abrev` está ordenado por `mes` (Ferramentas de
     Coluna, Classificar por coluna).
   - Valores, na ordem do legado: `[Qtd Prospect]`, `[Qtd Ativo]`,
     `[Ativo/Mês]`, `[Qtd Receptivo]`, `[Receptivo/Mês]`, `[Qtd Pastas]`,
     `[Pasta/Prospect]`, `[Pasta/Mês]`, `[QTD Vendas (incl. distratadas)]`,
     `[Vendas/Pastas]`, `[Vendas/Mês]`, `[VGV Bruto]` e, na última coluna,
     `[Farol Vendas]`.
   - Vale acrescentar `[Meses Ativos]` e `[Meses de Casa]` como colunas visíveis,
     pelo menos enquanto a página é nova. As duas juntas explicam sozinhas por que
     um corretor tem farol branco ou uma média mensal alta, e evitam a pergunta
     "esse número está certo?". Se quiser a data crua na dica de ferramenta,
     `dim_corretor_headcount[dt_contratacao]` já está lá.
   - Para ordenar por urgência, use `[Farol Ordem]` como coluna de ordenação
     (pode ficar oculta no visual).
   - Não filtre a matriz por `eh_ativo`. A dimensão traz o quadro inteiro, mas quem
     não teve movimento no período fica vazio em todas as medidas, inclusive no
     farol, e o Power BI esconde a linha sozinho. Filtrar por `eh_ativo` aqui traria
     de volta justamente o furo que a mudança resolveu, que é o corretor desligado
     no meio do ano sumir da tela com as vendas dele ainda no Total.

7. **Monte a matriz de gerentes** (visual Matriz), que é a visão por mês do outro
   lado da casa: linhas `dim_corretor_headcount[gerente]` e
   `dim_corretor_headcount[corretor]`, colunas `dim_calendario[mes_abrev]`,
   valores `[QTD Vendas (incl. distratadas)]` e `[VGV Bruto]`.

8. **Legenda do farol**: uma caixa de texto com as quatro linhas abaixo, que é o
   texto literal do legado.

   | Cor | Significado |
   |---|---|
   | 🟢 | vendeu no mês anterior ou atual |
   | 🟡 | vendeu no mês retrasado |
   | 🔴 | mais de 2 meses sem vender |
   | ⚪ | não apto ou entrada recente |

   Na v3 o branco também cobre quem já tem data de saída lançada, e vale ajustar a
   linha para "não apto, entrada recente ou desligado" se a página for para a mão do
   gestor sem explicação junto.

9. **Slicers**: o de data (Ano, Mês, Dia de `dim_calendario`) é obrigatório, não
   é enfeite. Sem nenhum filtro de período, `[Meses Ativos]` soma a série inteira
   desde 2022 e todas as médias por mês ficam pequenas demais. Junto dele,
   `dim_corretor_headcount[supervisor]` como Equipe e
   `dim_corretor_headcount[regional]`.

   Se puser um slicer de corretor, esse sim precisa de um filtro de visual em
   `eh_ativo` igual a Verdadeiro: a lista de um slicer mostra todos os valores da
   coluna, então sem o filtro ela viria com os 258 nomes da planilha, inclusive quem
   saiu em 2022. As linhas da matriz se resolvem sozinhas, a lista do slicer não.

Ao terminar, salve o arquivo com Ctrl+S. Medida criada por XMLA vive só no modelo
em memória até isso acontecer.

---

## 4. O que foi mudado de propósito em relação ao legado

Quatro diferenças, todas conscientes, e todas registradas também nos comentários do
arquivo `.dax`:

**A data de referência do farol.** O legado usava `MAX(d_calendario[Data])` puro.
Com a página filtrada no ano inteiro, a referência virava 31 de dezembro, o "mês
atual" virava dezembro, e o time inteiro aparecia vermelho de janeiro a novembro.
Na v3 a referência é limitada por `TODAY()`: com o ano inteiro selecionado o farol
fala do mês corrente, e com um mês passado selecionado ele mostra a foto daquela
época, que é o comportamento que se espera de um semáforo.

**O que conta como entrada recente.** O legado lia
`SELECTEDVALUE(f_headcount[Meses Ativos 2025])`, a coluna de resumo de um ano fixo:
em 2026 ela parou de crescer e o farol branco simplesmente deixou de acontecer. Na v3
a conta é tempo de casa de verdade, da data de contratação até a data de referência
da página, e a tolerância é de dois meses de calendário, o mês em que a pessoa entrou
e o seguinte. Junto disso entrou um caso que o legado não tinha: corretor com data de
desligamento já lançada sai da cobrança e fica branco, em vez de aparecer vermelho por
não ter vendido no mês em que estava de saída.

**O denominador das medidas por mês.** No legado o numerador vinha com
`REMOVEFILTERS(d_calendario)`, ou seja, ignorava o filtro de período da página,
enquanto o denominador era "Meses Ativos 2024 mais Meses Ativos 2025". A conta
misturava janelas diferentes e não obedecia ao slicer. Na v3 numerador e
denominador olham exatamente a mesma janela.

**Os nomes de duas conversões.** No legado, "Lead/Pasta" divide pastas por
prospects, e "Pasta/Venda" divide vendas por pastas. Os nomes dizem o contrário
da conta. Na v3 elas se chamam `Pasta/Prospect` e `Vendas/Pastas`, com o nome
antigo anotado no comentário para quem for comparar os dois relatórios lado a
lado.

Fora isso, a lógica é fiel: "venda" no farol continua sendo a definição larga,
Vendida e Distrato juntos (o "Qtd Vendas 2" do legado, KPI-08), porque o farol
mede atividade comercial e não VGV líquido. Quem vendeu e depois teve distrato
trabalhou.

---

## 5. Pendências e limites conhecidos

- **Quem saiu no meio do ano (resolvido em 10 de setembro de 2026).** Vale registrar
  o problema, porque a solução explica o formato da dimensão. Até então o DP-12
  carregava apenas os corretores marcados como Ativo, e como as linhas da matriz vêm
  da dimensão, o corretor desligado perdia a linha enquanto as vendas dele continuavam
  na fato: caíam todas juntas na linha em branco do relacionamento e seguiam contando
  no Total. Na tela isso apareceria como uma linha sem nome com um número grande, ou
  como um Total que não bate com a soma do que se vê.

  Não era hipótese. Em setembro de 2026 a planilha tem 14 corretores ativos, e três
  que estavam no quadro até agora viraram Inativo em agosto e setembro (Carlos
  Henrique Ferreira Costa, saída em 1 de agosto; Elizabete Maria Sousa do Nascimento,
  em 29 de agosto; Maisa Cristina de Paula e Silva, em 5 de setembro). Os três
  aparecem na página do legado, somando 12 das 77 vendas do ano e cerca de 3,5 dos
  21 milhões de VGV.

  O legado não tinha esse problema porque as linhas vinham de `f_headcount`, a
  planilha inteira, e o Power BI escondia sozinho quem não tivesse número no período.
  A v3 faz o mesmo agora: a dimensão carrega o quadro inteiro com `eh_ativo`, o farol
  devolve vazio para desligado sem movimento no período, e a linha some sozinha. Quem
  saiu com venda no período continua na tela, com o farol branco, e o Total fecha.

  Dois efeitos colaterais dessa mudança ficaram registrados de propósito. O join de
  `gold.dim_corretor` com o headcount passou a exigir `eh_ativo`, para que a `equipe`
  de quem já saiu continue vindo da derivação por reserva, como em todas as páginas
  que já estão no ar. E leads e pré-cadastros de corretor desligado, que antes não
  casavam com a dimensão, agora herdam Share, House/Parcerias e Regional pelo caminho
  do DP-13, o que preenche classificação que estava vazia em número histórico de
  outras páginas. O segundo é uma melhora, mas é uma melhora que muda número já
  publicado, então merece uma conferida na primeira carga.
- A comparação "pastas por corretor contra o headcount do mês", listada como
  pendência no `README.md` da pasta por falta da série mensal, agora é possível:
  a série existe, e `[Corretores Ativos]` entrega o headcount de qualquer
  período filtrado.
- O farol depende da carga de reservas estar em dia. Numa base parcial (o caso do
  banco local de desenvolvimento), corretor com venda recente pode aparecer
  vermelho só porque a reserva ainda não foi ingerida.
