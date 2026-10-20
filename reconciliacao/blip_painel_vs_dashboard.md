# Blip: por que o painel nativo e o dashboard v3 não batem

Levantamento feito em 10 de setembro de 2026, a partir da comparação que o
desenvolvedor fez entre as duas telas. Os números foram apurados chamando a API de
comandos do Blip direto, sem passar pelo banco, para separar o que é problema do
nosso pipeline do que é diferença entre as duas ferramentas.

Resumo em uma frase: a maior parte da diferença não é erro, são recortes diferentes,
mas existem dois problemas reais do nosso lado e um achado de infraestrutura que muda
a prioridade da carga diária.

---

## 1. O ponto de partida

| Tela | Tickets finalizados |
|---|---|
| Painel nativo do Blip | 900 |
| Dashboard v3 (página Atendimento) | 499 |

A proporção de aproximadamente 55 por cento se repetia em quase todas as linhas, de
fila e de atendente, o que sugeria um filtro a mais em algum lugar. Duas coisas não
se explicavam por filtro nenhum: a atendente Fernanda Teodoro, com 46 tickets no
painel e nenhuma linha no dashboard, e a tabela de empreendimentos, que mostrava
apenas dois produtos enquanto o painel mostrava oito.

---

## 2. O que a API devolve hoje

A coleção `/tickets` inteira, sem filtro nenhum, tem **1.207 tickets**. O `$skip=1207`
já volta vazio.

Desses, 1.190 foram criados a partir de **4 de agosto de 2026**, e os outros 17 são
registros soltos de fevereiro a maio de 2025. Pedir explicitamente tudo desde 1 de
junho de 2026 não traz nenhum ticket de junho nem de julho.

Distribuição por situação, nos 1.190 recentes:

| Situação na API | Tickets |
|---|---|
| ClosedAttendant | 819 |
| Transferred | 318 |
| ClosedClientInactivity | 28 |
| Open | 19 |
| Waiting | 6 |

Vale registrar que `ClosedClient` não aparece nenhuma vez. Na prática, o
"Finalizado" da nossa silver é hoje só o `ClosedAttendant`.

---

## 3. Causa 1: as duas telas estão em períodos diferentes

Varrendo todas as janelas possíveis e comparando fila a fila, o recorte que mais se
aproxima do dashboard v3 é **agosto de 2026, por data de fechamento**:

| Fila | API em ago/2026 | Dashboard v3 |
|---|---|---|
| DIRECT_TRANSFER | 205 | 206 |
| Relacionamento com cliente | 47 | 47 |
| Renegociação de Parcelas e Contratos | 48 | 50 |
| 2ª via de boleto | 150 | 173 |
| Default | 16 | 19 |
| Financiamento | 5 | 4 |

O painel do Blip, no mesmo teste, só se aproxima com uma janela que avança por
setembro. Ou seja, as duas telas estavam mostrando meses diferentes, e essa é a maior
parcela da diferença. Antes de qualquer outra conclusão, é preciso colocar as duas no
mesmo período.

Repare que em três filas o dashboard mostra um pouco **mais** que a API. Isso não é
erro, é a bronze fazendo o trabalho dela: ela guarda tickets que a API já descartou
(ver a seção 5).

---

## 4. Causa 2: "finalizado" quer dizer coisas diferentes nas duas telas

Para o Blip, um ticket transferido termina na fila e no atendente de origem, e um
novo ticket começa do outro lado. O painel conta esse encerramento como um ticket
finalizado. A nossa medida `[Tickets Finalizados]` conta apenas `ClosedAttendant` e
`ClosedClient`, e deixa `Transferred` de fora.

Não é um detalhe pequeno: são 318 tickets transferidos em 1.190, ou seja, 27 por
cento da base. É a segunda maior parcela da diferença, e explica por que Michele
Bueno aparece com 421 no painel e com 234 no dashboard: ela é quem mais recebe e
repassa atendimento.

Nenhuma das duas contagens está errada, elas respondem a perguntas diferentes.
"Quantas conversas foram concluídas" e "quantos atendimentos foram prestados" são
números legitimamente distintos quando existe transferência. O que faltava era ter as
duas disponíveis, então foi criada a medida `[Tickets Finalizados (padrão Blip)]`, que
inclui os transferidos e serve para conferir contra o painel.

---

## 5. Causa 3: a API do Blip só guarda cerca de cinco semanas

Este é o achado mais importante do levantamento, e ele não é sobre o dashboard.

A coleção `/tickets` tem 1.207 registros e começa em 4 de agosto de 2026. O painel
nativo do Blip mostra dados que a API simplesmente não devolve mais. A prova é a
Fernanda Teodoro: o painel atribui 46 tickets a ela, a API tem exatamente 2, e ela
nem aparece na lista de atendentes cadastrados. Nenhuma correção no nosso pipeline
traz esse histórico de volta, porque ele não está mais disponível na origem.

Isso corrige um número que estava registrado errado no projeto. O comentário em
`blip/api.py` falava em "coleção de aproximadamente 52 mil tickets". A confusão tem
uma explicação simples: os `sequentialId` dos tickets de hoje estão na casa dos 51
mil, e esse contador foi lido como se fosse o tamanho da coleção. Ele é um número que
só cresce, não uma contagem.

A consequência prática é séria. **A nossa bronze é a única memória de longo prazo
desse dado.** Enquanto a carga diária rodar, o histórico se acumula e fica nosso. No
dia em que ela parar por mais de cinco semanas sem ninguém perceber, o que passou
nesse intervalo se perde de forma definitiva. A tarefa agendada já existe na VM e
roda `ingerir_blip.py --full` uma vez por dia, o que é barato agora que se sabe que a
coleção inteira cabe em treze páginas. O que muda é a prioridade de monitorá-la.

---

## 6. Causa 4: a tag de empreendimento quase não chega ao dashboard

Este é um problema nosso, isolado e com correção conhecida.

Os tickets trazem 13 códigos de empreendimento na tag, e apenas 2 chegam à tabela do
dashboard. O motivo é que `silver.conformar_empreendimento` faz correspondência
exata contra a coluna `Produto` da aba `DE_PARA_PRODUTOS`, e a grafia do Blip tem duas
diferenças sistemáticas: o sufixo da regional e a falta de acento.

| Tag do Blip | Tickets | Situação | Conformado sugerido |
|---|---|---|---|
| PDO - Parc das Orquideas RP | 90 | não casa | Parc das Orquídeas |
| F16 - Fiusa 016 RP | 64 | não casa | Fiusa 016 |
| TFR - Triade RP | 54 | não casa | Tríade Fiúsa (confirmar) |
| PDP - Parc das Primaveras RP | 53 | não casa | Parc das Primaveras |
| VLP - Villas do Parque | 23 | não casa | ambíguo, ver abaixo |
| PDA - Parc das Artes RP | 12 | não casa | Parc Das Artes |
| PCJ - Parc Cidade Jardim | 11 | casa | Parc Cidade Jardim |
| QDV - Quinta dos Ventos Pitangueiras | 9 | não casa | Quinta dos Ventos |
| PSU - Parc Sul Uberaba | 8 | casa | Parc Sul Uberaba |
| VLM - Villa Manacá | 7 | não casa | Villa Manacás |
| VDP - Villas do Paraty Bebedouro | 4 | não casa | Villas De Paraty |
| ARB - Arboretto RP | 2 | não casa | Arboretto |
| PSR - Parc Sul Ribeirão | 1 | não casa | Parc Sul Residence (confirmar) |

Dois casos precisavam de decisão de quem conhece o produto, e não de código, e foram
decididos em 14 de setembro de 2026. "Parc Sul Ribeirão" é o "Parc Sul Residence",
confirmado. "Villas do Parque" vai para "Villas do Pq. Lote", seguindo a regra que o
backoffice já usava na própria aba: a grafia sem qualificador ("Villas Do Parque
Residencial", linha 22) sempre foi Lote, e só "- Casa/Casas" é Casa. A tag do Blip é
uma só para os dois produtos, então ticket de comprador de casa vai aparecer em Lote;
se isso pesar, a saída é o Blip criar duas tags e a de-para ganhar as duas grafias.
O que NÃO dá para fazer é juntar Casa e Lote num nome conformado só: a
`dim_empreendimento` tem uma linha por produto do CRM, e duas linhas com o mesmo
nome conformado duplicariam cada ticket no join da `fato_atendimentos` (e o mesmo
vale para metas e viabilidade, que também casam por esse nome).

A correção das grafias é acrescentar uma linha por grafia na aba `DE_PARA_PRODUTOS`
da planilha Vendas Consolidadas, que é exatamente o caminho que a de-para foi
desenhada para resolver. Nada de SQL novo. **Feito em 14 de setembro de 2026**
(linhas 28 a 38 da aba, onze grafias; "Parc Cidade Jardim" e "Parc Sul Uberaba" já
casavam). Depois de recarregar as seeds com `popular_seeds.py --xlsm`, a consulta
`SELECT * FROM gold.blip_tags_sem_empreendimento` deve voltar vazia, e ela existe
justamente para essa conferência.

---

## 7. Causa 5: motivo de encerramento não mostra "Inatividade"

O dashboard lista "Cliente indisponível", "teste" e "horarioexpirado", mas nunca
"Inatividade", mesmo havendo 28 tickets com essa tag. A explicação está na cadeia de
definições: o status `ClosedClientInactivity` vira a situação "Abandonado" na silver,
e a tabela de motivos usa `[Tickets Finalizados]`, que não inclui abandonados.

Está coerente com o desenho, mas é confuso na tela, porque o gestor vê uma tag do
Blip desaparecer sem explicação. Vale trocar a medida da tabela de motivos por
`[Tickets Fechados]`, que inclui os abandonados, ou acrescentar uma coluna separando
os dois. Fica anotado como decisão em aberto.

---

## 8. Detalhe que vale conhecer: os 47 sem atendente

Os 47 tickets que aparecem como "Sem atendente identificado" no dashboard são todos
da fila "Relacionamento com cliente", todos com status `ClosedAttendant`, e nenhum
deles tem data de abertura nem de primeira resposta, só data de fechamento.

São conversas encerradas sem nunca terem sido atendidas por uma pessoa. Por isso a
linha aparece com traços em todas as colunas de tempo, e não porque falte
processamento. Essa fila tem, além desses 47, mais 73 tickets transferidos e 4 em
espera.

---

## 9. Dá para replicar o painel exatamente? Não pela API

Pergunta feita logo depois deste levantamento, e a resposta é não, com prova.

O primeiro teste foi promissor. Procurando qual janela reproduz os 421 tickets da
Michele Bueno, existe exatamente uma: tickets criados entre 19 de agosto e 10 de
setembro, contando os transferidos. Só que, nessa mesma janela, o resto da tabela não
acompanha:

| Atendente | API nessa janela | Painel |
|---|---|---|
| Michele Bueno | 421 | 421 |
| Roberta Zeola | 84 | 53 |
| Beatriz Bin | 62 | 40 |
| ariana.barcellos | 56 | 34 |
| Regiane Padilha | 38 | 51 |
| Juliana da Silva Freitas | 19 | 30 |
| Fernanda Teodoro | 0 | 46 |

Ou seja, o 421 foi coincidência. Não existe recorte da API que produza a tabela do
painel, porque o painel não está olhando o mesmo conjunto de tickets.

Também não existe atalho por outro endpoint. Foram testados, um a um,
`/metrics`, `/reports`, `/analytics`, `/tickets/metrics`, `/attendants/metrics`,
`/queues`, `/tags`, `/closing-reasons` e `/service-hours` na extensão do Desk: todos
recusados com "no processor available". O que existe é `/agents` (igual a
`/attendants`), `/rules` (regras de distribuição) e, na extensão de analytics,
`/reports`, que devolve apenas o cadastro dos relatórios que as pessoas criaram no
portal, sem nenhum dado dentro.

E a coluna "Atingimento SLA" do painel não tem campo correspondente no ticket. A
regra de SLA é configuração do portal, não dado da API, então ela só pode ser
reimplementada se alguém ler a configuração e nos disser qual é.

**O caminho que funciona é outro: exportar do próprio painel.** As três abas têm
botão de download no canto superior direito. Com o CSV do painel e a nossa base na
mesma janela, a conferência deixa de ser adivinhação e vira comparação ticket a
ticket, que é o que permite ajustar cada definição com certeza em vez de por
tentativa.

Uma boa notícia que saiu desse teste: ao contrário do que estava documentado, o
`$filter` do `/tickets` funciona em `closeDate`, `statusDate`, `openDate`, `status` e
`team`, e não só em `storageDate`. Foi conferido que ele restringe de verdade, e não
é ignorado em silêncio (`closeDate ge 2026-09-01` devolve 533 de 1.208, `status eq
'ClosedAttendant'` devolve 819). Isso abre a porta para um incremental por
`statusDate`, que é a data que se move quando o ticket muda.

---

## 10. O que fazer, em ordem

1. Colocar as duas telas no mesmo período antes de comparar qualquer número. Enquanto
   isso não for feito, o resto da comparação não significa nada.
2. Usar `[Tickets Finalizados (padrão Blip)]` quando o objetivo for conferir contra o
   painel, e manter `[Tickets Finalizados]` como a leitura de conversas concluídas.
3. Feito em 14/set/2026: onze grafias acrescentadas na aba `DE_PARA_PRODUTOS`, "Parc
   Sul Ribeirão" amarrado ao Parc Sul Residence e "Villas do Parque" ao Villas do Pq.
   Lote (seção 6). Falta recarregar as seeds em produção e conferir com
   `gold.blip_tags_sem_empreendimento`.
4. Monitorar a tarefa agendada de ingestão do Blip com atenção maior do que a das
   outras. Ela é a única coisa que impede a perda definitiva do histórico de
   atendimento.
5. Decidir se a tabela de motivos passa a incluir os abandonados.
