# Perfil do Cliente: como replicar e melhorar a página do legado (DP-15)

Este documento é um mapa visual a visual, no mesmo espírito do `PAGINA_PRECO.md`
para o BI de Preço. Foi extraído do `Report/Layout` do `BI V.2/BI Matriz/BI
Matriz.pbix` (zip mais JSON em UTF-16) em 25 de agosto de 2026, decompondo os
`visualContainers` de cada página: tipo de visual, campo usado em cada papel
(categoria, valor) e filtros aplicados a nível de página e de visual.

Existe também um arquivo separado, `Relatórios Comercial/Perfil Clientes/Perfil
de Clientes - Pafil.pbix`, com um nome parecido. Ele não tem relação com esta
página: suas páginas se chamam "Primaveras", "Orquideas", "Fiusa 016",
"Arboretto" e "Tá Fácil na Pafil", e tratam de outro assunto. Para efeito deste
levantamento, ele foi descartado.

As medidas ficam em [`powerbi/MEDIDAS_PERFIL_CLIENTE.dax`](MEDIDAS_PERFIL_CLIENTE.dax).
A montagem em si, como o resto do `.pbix`, é manual no Power BI Desktop.

---

## 1. Como o legado está organizado

Dentro do `BI Matriz.pbix` existem três páginas quase idênticas: "Perfil do
Cliente" (21 visuais), "Perfil do Cliente Pré Cadastro" (16 visuais) e "Perfil
do Cliente Reserva" (20 visuais). Há ainda duas páginas pequenas, "profissão
detalhada" e "idade" (1 visual cada, com dimensão de canvas muito menor que as
demais, 320x222 e 132x240 contra o padrão 4203x5000), que parecem ser páginas de
tooltip ou de apoio para drill-down, não páginas de navegação normal.

Um achado central desta auditoria: **nenhuma das três páginas tem uma única
medida DAX própria.** Todo cartão, coluna ou rosca usa agregação implícita
(`Sum`, `CountNonNull`) direto sobre uma coluna, seja da tabela `perfil cliente`
(importada do CSV de 148 colunas documentado em DP-15 no `docs/regras-de-negocio.md`),
seja de uma segunda tabela quase igual, `perfil cliente pré cadastro`. Isso já é
um ponto de partida importante: a v3, ao criar medidas nomeadas em
`MEDIDAS_PERFIL_CLIENTE.dax`, já parte na frente do legado em governança, mesmo
antes de qualquer melhoria de cálculo.

### 1.1 A estrutura visual, comum às três páginas

Descontando os divisores (retângulos usados como linha entre seções) e o
logotipo, cada página tem sempre o mesmo conjunto de 9 visuais de dado:

| Visual | Tipo | Campo (papel Categoria) | Campo (papel Valor) |
|---|---|---|---|
| ESTADO CIVIL | rosca | `perfil cliente.Estado Civil` | `CountNonNull(f_precadastros.Id)` |
| GÊNERO | rosca | `perfil cliente.Gênero` | `CountNonNull(f_precadastros.Id)` |
| PROFISSÃO | coluna | `perfil cliente.profissões ajustado` | `CountNonNull(f_precadastros.Id)` |
| FAIXA ETÁRIA | coluna | `perfil cliente.Faixa Etária` | `CountNonNull(f_precadastros.Id)` |
| CIDADE | coluna | `perfil cliente.Cidade` | `CountNonNull(f_precadastros.Id)` |
| FAIXA DE RENDA | coluna | `perfil cliente.Faixa de Renda` | `CountNonNull(f_precadastros.Id)` |
| BAIRRO | coluna | `perfil cliente.Bairro` | `CountNonNull(f_precadastros.Id)` |
| card (rotulado "qtd") | cartão | | `Sum(perfil cliente.Idade)` |
| card (rotulado "qtd") | cartão | | `Sum(perfil cliente.Renda)` |

Acima dos gráficos, sempre a mesma faixa de filtros: slicers de Empreendimento,
Regional e Assinatura (`d_empreendimentos`), um slicer de Mês em largura cheia,
e mais Ano e Etapa do pré-cadastro (`f_precadastros.Etapa precadastro BI`).

Duas colunas, `Faixa Etária` e `Faixa de Renda`, não existem no CSV de origem
(conferido no cabeçalho de `perfil_cliente_precadastro.csv`, que tem `Idade` e
`Renda` como valores crus, sem faixa). São colunas calculadas dentro do próprio
modelo Power BI. Como o `DataModel` de um `.pbix` é um binário compactado
(VertiPaq), não deu para ler a fórmula exata dessas colunas nesta auditoria sem
abrir o arquivo no Desktop; o corte por faixa que a gold já implementa em
`gold.dim_perfil_cliente` (`faixa_etaria`, `faixa_renda_mcmv`) foi desenhado de
forma independente, com os pontos de corte do MCMV vigente, então os rótulos das
faixas provavelmente não vão bater com os do legado ao pé da letra. Vale
confirmar lado a lado se isso importar para a gestão.

`profissões ajustado`, usada no gráfico de Profissão, também não é uma coluna
crua do CSV (o CSV só tem `Profissão (Selecionado)` e `Profissão (Preenchido)`).
A existência de uma segunda página oculta, "profissão detalhada", com uma
coluna chamada `profissões detalhadas`, sugere que o legado já tinha dois
níveis de categorização de profissão, igual ao desenho de DP-07
(`silver.dpara_profissoes`, com colunas `Macro` e `Micro`). Isso é uma boa
notícia: a v3 já reproduz essa mesma ideia de dois níveis
(`profissao_macro`/`profissao_micro`), então não é preciso inventar nada novo
aqui, só confirmar que o corte de categorias bate.

---

## 2. Achados: o que não vale a pena replicar

### 2.1 "Perfil do Cliente" e "Perfil do Cliente Reserva" são a mesma página

Comparando os dois JSONs visual a visual, as duas páginas têm exatamente os
mesmos 9 visuais de dado, os mesmos 6 slicers, os mesmos filtros de "excluir
vazio" em cada visual, e até os mesmos identificadores internos de filtro (por
exemplo, o filtro do gráfico de Estado Civil tem o mesmo `name`,
`f5c7bee3062c17dbcc40`, nas duas páginas). Não existe nenhum filtro de página
ou de visual que diferencie uma da outra. Na prática, hoje elas mostram sempre
o mesmo número, para o mesmo clique de slicer. A explicação mais provável é que
uma foi copiada da outra num momento de retrabalho, com a intenção de
diferenciar mais tarde algo que nunca chegou a acontecer, não uma escolha de
design deliberada.

**Recomendação:** não recriar as duas. Uma cobre a outra.

### 2.2 "Perfil do Cliente Pré Cadastro" está travada num único empreendimento

Essa página não tem os slicers de Empreendimento, Regional e Assinatura que as
outras duas têm (16 visuais contra 20/21, e a contagem bate: 5 divisores + 2
slicers, contra 5 divisores + 6 slicers nas outras). Em compensação, ela carrega
um filtro de página fixo: `Empreendimento = 'Parc Cidade Jardim'`. Ou seja,
quem abre essa página hoje sempre vê só os dados de Parc Cidade Jardim, sem
nenhum jeito de trocar pela interface. Isso não é um recorte proposital: é
quase certo que a página foi construída ou testada para o lançamento de Parc
Cidade Jardim especificamente e nunca foi generalizada depois.

Some-se a isso uma segunda inconsistência: nessa mesma página, os visuais de
GÊNERO, FAIXA ETÁRIA e o cartão de Renda apontam para a tabela **`perfil cliente
pré cadastro`** em vez de `perfil cliente`, usada por todos os outros visuais
(inclusive os outros da própria página, como Estado Civil, Profissão, Cidade,
Bairro). É uma migração parcial: alguém trocou a fonte de alguns visuais para
uma tabela nova e esqueceu o resto.

Um terceiro problema, específico dessa tabela alternativa: o cartão de GÊNERO
usa `Sum(perfil cliente pré cadastro.N.)` como valor. A coluna `N.` é a mesma
coluna de numeração de linha já documentada em DP-15 no `docs/regras-de-negocio.md`
(874 repetições em 7.805 linhas, não é uma chave única). Somar uma coluna de
numeração de linha não produz uma contagem válida de nada; o valor exibido
nesse card provavelmente já está errado hoje.

**Recomendação:** não replicar essa página como está. Se a intenção original
era mostrar o funil de crédito (pré-cadastro) separado de quem comprou
(reserva), isso já é coberto pelo corte "Comparativo" descrito na seção 4, sem
travar em um único empreendimento.

### 2.3 Os cartões "qtd" somam idade e renda em vez de agregar de forma útil

Os dois cartões de cada página, ambos rotulados genericamente "qtd" (não
"Idade Média" nem "Renda Média"), usam `Sum` sobre `Idade` e sobre `Renda`.
Somar a idade de centenas de pessoas, ou a renda de centenas de pessoas, produz
um número grande sem leitura de negócio (não é nem total, nem médio, nem
típico). O rótulo genérico "qtd" sugere que ninguém chegou a nomear o cartão
depois de configurá-lo, um sinal de que ficou incompleto. A v3 já resolve isso
com `Idade Mediana` e `Renda Mediana` em `MEDIDAS_PERFIL_CLIENTE.dax`, usando
mediana em vez de média para não deixar os valores de teto do CSV (documentado
em DP-15, entradas de R$ 99.999.999,99) distorcerem o número.

### 2.4 O rótulo "EMPREENDIMENTO" está no slicer errado

Nas páginas "Perfil do Cliente" e "Perfil do Cliente Reserva", o texto
"EMPREENDIMENTO" é o título do slicer de largura cheia que fica logo abaixo da
fileira de filtros pequenos, mas esse slicer específico está de fato ligado à
hierarquia de mês do `d_calendario`, não a empreendimento (o slicer de
empreendimento de verdade é o pequeno, sem título, ao lado). É só um problema
cosmético de rótulo, provavelmente sobrado de uma cópia de outro slicer; não
compromete o filtro, e não precisa virar um problema a resolver, só não vale a
pena reproduzir o rótulo ao pé da letra.

### 2.5 A contagem sempre passa por pré-cadastro, mesmo na página de vendas

Um ponto sutil: em todos os gráficos das três páginas, o valor é
`CountNonNull(f_precadastros.Id)`, ou seja, conta linhas de pré-cadastro, não
pessoas distintas. Se uma pessoa tiver mais de um pré-cadastro (mais de uma
tentativa, ou mais de um empreendimento), ela é contada mais de uma vez em cada
corte. Isso é diferente do que a v3 já propõe com `Perfis Cadastrados`
(`DISTINCTCOUNT` de `documento_chave`, contagem de pessoas distintas). Nenhuma
das duas está errada, são perguntas diferentes ("quantas entradas de funil têm
esse perfil" contra "quantas pessoas distintas têm esse perfil"), mas a v3
deveria escolher de forma consciente qual das duas cada gráfico responde, em
vez de herdar a contagem de pré-cadastro por padrão como o legado fez. A seção
4 trata isso corte a corte.

---

## 3. Atenção crítica para a montagem no Desktop: direção do relacionamento

`docs/modelo-semantico.md` já documenta que `dim_perfil_cliente[documento_chave]`
relaciona com `fato_reservas`/`fato_precadastros` como 1 para muitos, e
recomenda nunca ativar as duas relações ao mesmo tempo (para não formar um
losango de filtro com `dim_empreendimento`). O que ainda não estava registrado,
e é essencial para esta página funcionar: por padrão, esse tipo de
relacionamento propaga filtro só de dimensão para fato, não o contrário. Como
todos os slicers planejados para esta página (Empreendimento, Regional,
Assinatura, Mês, Ano) filtram `dim_empreendimento`/`dim_calendario`, que por
sua vez filtram `fato_reservas`/`fato_precadastros`, mas **não**
`dim_perfil_cliente` diretamente, nenhum desses slicers vai afetar `Renda
Mediana`, `Idade Mediana` ou qualquer outra medida de `dim_perfil_cliente`,
enquanto a direção do filtro estiver no padrão. O corte "Comparativo por
empreendimento" e a evolução mensal, descritos na seção 4, simplesmente não
vão responder ao clique do usuário.

**Antes de montar os visuais, em Gerenciar relacionamentos:** troque a direção
do filtro cruzado da relação `dim_perfil_cliente` ativa (a de `fato_reservas`
ou a de `fato_precadastros`, dependendo de qual bloco da página) para "Ambas".
Como só uma das duas fica ativa por vez, essa troca não reabre o risco de
losango já documentado.

---

## 4. O novo desenho: de 3 páginas para 1

Com os achados da seção 2, a recomendação de consolidar fica mais forte do que
uma simples redução de manutenção: duas das três páginas legadas
(2.1 e 2.2) não são visões legítimas e diferentes, são uma duplicata morta e
uma página quebrada presa a um único empreendimento. Não existe, no legado,
nenhuma página de Perfil do Cliente que hoje funcione corretamente para
comparar entre empreendimentos.

**Recomendação:** uma página só, "Perfil do Cliente", relacionada por padrão a
`fato_reservas` (cobre "quem comprou"), com um segundo bloco de cartões e
gráficos relacionado a `fato_precadastros` (cobre "quem entrou no funil de
crédito", incluindo quem não comprou). Se o volume de visuais crescer demais
para uma página só, separar em duas ("Perfil - Vendas" e "Perfil - Funil de
Crédito") continua sendo melhor do que voltar a ter três páginas quase iguais.

### 4.1 Cortes recomendados

| Seção | Medida/coluna | Fonte na gold | Origem |
|---|---|---|---|
| Resumo | `Perfis Cadastrados`, `Renda Mediana`, `Idade Mediana`, `% Com Renda Informada` | `dim_perfil_cliente` | novo (o legado usava dois cartões "qtd" quebrados, ver 2.3) |
| Sexo | `% Feminino`, rosca por `dim_perfil_cliente[sexo]` | `dim_perfil_cliente` | carryover (GÊNERO) |
| Estado civil | rosca por `dim_perfil_cliente[estado_civil]`, `% Solteiro` | `dim_perfil_cliente` | carryover (ESTADO CIVIL) |
| Faixa etária | coluna por `dim_perfil_cliente[faixa_etaria]`, cruzado com `Renda Mediana` | `dim_perfil_cliente` | carryover (FAIXA ETÁRIA), pontos de corte novos, ver 1.1 |
| Faixa de renda / MCMV | coluna por `dim_perfil_cliente[faixa_renda_mcmv]` | `dim_perfil_cliente` | carryover (FAIXA DE RENDA), pontos de corte novos |
| Profissão | coluna por `dim_perfil_cliente[profissao_macro]`, drill-down para `profissao_micro`, com `% Com Profissão Identificada` como nota de cobertura | `dim_perfil_cliente` + DP-07 | carryover (PROFISSÃO + "profissão detalhada") |
| Origem geográfica | coluna por `dim_perfil_cliente[cidade]` e por `[bairro]` | `dim_perfil_cliente` | carryover (CIDADE, BAIRRO, a última faltava no desenho anterior deste documento) |
| Comprometimento de renda | `Comprometimento de Renda` (parcela aprovada dividida pela renda) | `fato_precadastros[valor_prestacao]` / `dim_perfil_cliente[renda]` | novo, não existia no legado |
| PPE / compliance | `% PPE`, tabela com `pessoa_lista_suspeitos`/`residente_municipio_fronteira` quando `TRUE` | `dim_perfil_cliente` | novo, não existia no legado |
| Mídia/origem do lead | reaproveita `dim_origem`, já relacionada a `fato_precadastros`/`fato_leads` | `dim_origem` | novo, não existia no legado |
| Evolução mensal | `Renda Mediana`/`Idade Mediana` por `dim_calendario[ano_mes]` (via `fato_reservas[data_venda]`) | `dim_perfil_cliente` + `dim_calendario` | novo, não existia no legado |
| Comparativo por empreendimento | os mesmos cortes acima, com `dim_empreendimento[empreendimento]` como slicer | `dim_perfil_cliente` + `dim_empreendimento` | carryover do conceito (slicer de Empreendimento/Regional/Assinatura já existia), exige a correção da seção 3 |

A coluna "Origem" existe de propósito: ela separa o que é reconstrução fiel do
legado (a maioria dos gráficos) do que é acréscimo desta v3 (Comprometimento de
Renda, PPE, Mídia, Evolução mensal). Isso ajuda a conversa com a gestão: os
acréscimos são os que precisam de validação de utilidade, não só de
reconciliação de número.

**Sobre a contagem (seção 2.5):** nos cortes de Sexo, Estado civil, Faixa
etária, Faixa de renda, Profissão e Origem geográfica, o valor recomendado é
`Perfis Cadastrados` (pessoas distintas), diferente do legado, que contava
pré-cadastros. Se a gestão preferir manter a semântica antiga (contar entradas
de funil, não pessoas), existe `Entradas no Funil` em
`MEDIDAS_PERFIL_CLIENTE.dax`, pronta para substituir sem precisar reescrever o
gráfico.

---

## 5. Mapeamento de campos, legado para gold

| Campo no legado (`perfil cliente` / `perfil cliente pré cadastro`) | Coluna em `gold.dim_perfil_cliente` |
|---|---|
| Estado Civil | `estado_civil` |
| Gênero | `sexo` |
| Idade | `idade` |
| Nacionalidade | (fora de escopo na gold, ver DP-15 no `docs/regras-de-negocio.md`) |
| Naturalidade | (fora de escopo) |
| Bairro | `bairro` |
| Cidade | `cidade` |
| Profissão (Selecionado) / profissões ajustado | `profissao_selecionado` / `profissao_macro` |
| Profissão (Preenchido) / profissões detalhadas | `profissao_preenchido` / `profissao_micro` |
| Renda | `renda` (atenção a `tem_renda_informada`, ver ressalva 6.1) |
| Faixa Etária (coluna calculada) | `faixa_etaria` (pontos de corte próprios da v3) |
| Faixa de Renda (coluna calculada) | `faixa_renda_mcmv` (pontos de corte próprios da v3) |
| Pessoa residente em município de faixa de fronteira | `residente_municipio_fronteira` |
| (sem equivalente no CSV, PPE vem só da API) | `pessoa_politicamente_exposta`, `eh_ppe`, `ppe_cargo` |
| `f_precadastros.Etapa precadastro BI` | `fato_precadastros[etapa_bi]` |

As colunas do CSV fora dessa lista (dados bancários, PJ, terceiros do bloco
PPE, documentos como RG/CNH) foram excluídas por decisão de escopo e LGPD,
documentada em DP-15 no `docs/regras-de-negocio.md` e em `docs/modelo-semantico.md`. Se a
gestão precisar delas para um caso de uso específico (por exemplo, auditoria de
compliance), a extensão certa é trazer mais colunas de
`bronze.pessoas`/`bronze.pessoas_profissional`, não reabrir a fonte manual.

---

## 6. Ressalvas técnicas a levar para o Desktop

Herdadas do relatório ad-hoc, da investigação de DP-15 e desta auditoria:

- **6.1 Renda vem 0, não `NULL`, quando não preenchida.** Sempre filtrar
  `tem_renda_informada = TRUE` (ou `renda > 0`) e usar mediana, nunca média
  crua. A digitação é livre no CVCRM, sem validação: valores no teto de
  R$ 99.999.999,99 continuam existindo na fonte, e são justamente o tipo de
  outlier que o cartão "qtd" do legado (seção 2.3) deixava passar direto para
  a soma.
- **6.2 A fonte de profissão/renda mudou no mesmo dia (24 de agosto de 2026),
  de CSV manual para a API CVDW** (`bronze.pessoas` mais
  `bronze.pessoas/profissional`, endpoint novo, ver DP-15 em
  `docs/regras-de-negocio.md` para o histórico completo da investigação). A taxa de
  match de `documento_chave` contra `fato_reservas` subiu de 85,9% para 96,9%,
  e o caso mais crítico do CSV (Residencial Quinta dos Ventos, vendas de 2026,
  que batia só 9,5% porque o CSV era um snapshot parado em agosto de 2025) foi
  para 95,2%. O CSV manual continua no repositório só como fallback silencioso
  (`fonte_perfil='precadastro'` na dimensão); não precisa mais de reexportação
  manual para manter a página atualizada.
- **6.3 Cobertura de profissão é real, não um problema de junção**:
  `profissao` está 65,7% preenchida na fonte (medido na carga completa, 8.465
  registros). Mostrar `% Com Profissão Identificada` perto de qualquer visual
  de profissão evita que alguém leia a lacuna residual (cerca de 34%) como bug.
- **6.4 PPE e a lista de indivíduos suspeitos têm cobertura baixa por
  natureza** (poucas pessoas se enquadram); não é falha de dado.
- **6.5 Sem banco, sem PJ, sem documento de identidade na gold**, decisão de
  escopo e LGPD (DP-15 em `docs/regras-de-negocio.md`).
- **6.6 A direção do relacionamento precisa ser trocada para "Ambas"** antes
  de montar qualquer visual que combine um slicer de empreendimento/data com
  uma medida de `dim_perfil_cliente` (ver seção 3). Sem essa troca, os
  cartões de Renda/Idade Mediana vão parecer "travados", sempre mostrando o
  total geral, não importa o que o usuário clique.
- **6.7 Não recriar as três páginas do legado.** "Perfil do Cliente Reserva" é
  uma cópia morta de "Perfil do Cliente" (seção 2.1), e "Perfil do Cliente Pré
  Cadastro" está presa a um único empreendimento por um filtro esquecido
  (seção 2.2). Nenhuma das duas é uma segunda fonte de verdade a preservar.

---

## 7. Pendências e decisões que dependem da gestão

- **Faixas de idade e de renda:** os pontos de corte usados na v3
  (`gold.dim_perfil_cliente.faixa_etaria`/`faixa_renda_mcmv`) foram desenhados
  de forma independente do legado, porque a fórmula das colunas calculadas do
  legado está dentro do binário do modelo e não foi extraída nesta auditoria.
  Se a gestão já está acostumada com as faixas antigas, vale abrir o legado no
  Desktop uma vez e comparar os rótulos lado a lado antes de finalizar os
  eixos dos gráficos.
- **Semântica de contagem** (seção 2.5 e 4.1): decidir, corte a corte, se o
  número certo é `Perfis Cadastrados` (pessoas distintas) ou `Entradas no
  Funil` (linhas de pré-cadastro, replicando o comportamento antigo). A
  recomendação deste documento é pessoas distintas por padrão, com a medida
  alternativa disponível para quem preferir manter a leitura antiga.
- **Página "Perfil do Cliente Pré Cadastro":** confirmar com quem usava essa
  página se o filtro fixo em Parc Cidade Jardim era intencional (por exemplo,
  um recorte usado só durante aquele lançamento) antes de assumir que é bug
  e descartar de vez.
- **Utilidade dos cortes novos** (Comprometimento de Renda, PPE, Mídia,
  Evolução mensal): como não existiam no legado, valem uma conversa curta com
  quem vai usar a página antes de considerá-los definitivos.
