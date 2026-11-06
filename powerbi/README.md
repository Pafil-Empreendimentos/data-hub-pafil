# Power BI sobre a camada gold: passo a passo de importação

**Atenção:** o arquivo `de_para_classificacao.xlsx`, guardado nesta mesma pasta,
contém dado real (nomes e classificações de proposta). Mantenha o repositório privado e
não redistribua esse arquivo.

Este é o guia para montar o `.pbix` da apresentação mensal, consumindo o star
schema da camada gold, substituindo a cadeia manual de CVCRM até Vendas
Consolidadas até PBIX. A gold já entrega os fatos e as dimensões reconciliados (o
VGV bate com os slides atuais); rankings, mídia e a esteira são montados
diretamente no Power BI.

---

## 0. Pré-requisitos

1. **O banco precisa estar de pé.** Num Postgres local, basta o serviço ativo. Para ler a
   produção, abra o túnel SSH (veja [`infra/README.md`](../infra/README.md)).
2. **O warehouse precisa estar aplicado:** `python aplicar_tudo.py` (que roda
   silver, gold e seeds em sequência). Para ter os nomes conformados e o House
   completos, rode também `python aplicar_tudo.py --xlsm "<Vendas Consolidadas.xlsm>"`
   e `python popular_seeds.py --gerentes "<depara_gerentes.xlsx>"`.
3. **O provedor Npgsql:** na primeira conexão com o PostgreSQL, o Power BI
   Desktop vai pedir para instalar o Npgsql. Aceite a instalação (ou, se preferir,
   baixe direto do GitHub do Npgsql e reinicie o Desktop depois).

---

## 1. Conectar ao banco

**Opção A, mais rápida:** dê um duplo clique em `conectar_gold.pbids`. Isso já
abre o Power BI Desktop conectado ao banco.

**Opção B, manual:** vá em Página Inicial → Obter dados → Banco de dados → Banco
de dados PostgreSQL:
- **Servidor:** `localhost:<porta>` (a do seu `.env`: `5433` pelo túnel de produção)
- **Banco de dados:** `pafil_dw`
- **Modo:** Importar
- Nas credenciais, na aba Banco de dados: o usuário `pafil_bi` (somente leitura) para
  produção, ou o usuário e a senha do seu banco local. A senha de produção fica na máquina
  do banco, e não neste repositório.
- Se o Power BI reclamar de SSL ou criptografia, lembre que a conexão por túnel roda
  sem SSL: desmarque a opção "Criptografar conexão" (ou responda que quer
  conectar sem criptografia quando for perguntado).

---

## 2. Selecionar as tabelas, na tela do Navegador

Marque, dentro do schema `gold`:

| Objeto | Para que serve |
|---|---|
| `fato_reservas` | a tabela fato, base de todas as análises de venda |
| `dim_calendario` | o eixo de tempo, usado em análises por mês e no acumulado do ano (YTD) |
| `dim_empreendimento` | usada em Vendas por Empreendimento |
| `dim_corretor` | traz os atributos de cada corretor |
| `fato_leads` | o funil de marketing, cruzando leads com mídia e origem |
| `fato_precadastros` | o funil de crédito, com os pré-cadastros |
| `dim_corretor_headcount` | o quadro do backoffice: corretor, equipe, regional, a flag `eh_ativo`, as datas de entrada e saída e o tempo de casa em meses. É a dimensão que dá as linhas da página Performance. Carrega ativos e desligados, então em slicer de corretor filtre `eh_ativo` |
| `fato_headcount_mensal` | a série de meses ativos por corretor (DP-16), denominador das medidas por mês e insumo do farol |

> A gold entrega apenas fatos e dimensões. Rankings, Vendas por Mídia, a esteira e
> os demais agregados são montados diretamente no Power BI, como medidas e
> visuais sobre `fato_reservas`, usando a classificação oficial (origem, canal,
> mídia, House ou Parcerias) que vem da Vendas Consolidadas, mesclada por
> proposta. Use "Transformar Dados" só se quiser revisar algo antes; caso
> contrário, clique direto em Carregar.

---

## 3. Configurar os relacionamentos (modo Modelo)

As dimensões se ligam à fato sempre na direção de um para muitos:

```
dim_calendario[data]              1─* fato_reservas[data_venda]      (ativo)
dim_empreendimento[id_empreendimento] 1─* fato_reservas[id_empreendimento]
dim_corretor[id_corretor]         1─* fato_reservas[id_corretor]
```

- Marque `dim_calendario` como Tabela de Datas, usando a coluna `data`: vá em
  Ferramentas de Tabela → Marcar como tabela de datas.
- `fato_leads` e `fato_precadastros` se ligam a `dim_calendario` pela coluna
  `data_cad` (e, quando fizer sentido, também a `dim_empreendimento` e
  `dim_corretor`), para alimentar os funis de marketing e de crédito.
- Opcionalmente, crie um relacionamento inativo entre `dim_calendario[data]` e
  `fato_reservas[data_distrato]`, para analisar distratos pelo mês em que o
  distrato aconteceu (ativando esse relacionamento com `USERELATIONSHIP` dentro
  da medida específica).

---

## 4. Criar as medidas

Cole o conteúdo de `MEDIDAS_GOLD.dax` em uma tabela de medidas. Ele já traz VGV
Bruto, VGV Distrato, VGV Líquido, QTD, Ticket Médio, Taxa de Distrato, YTD e
variação mês a mês (MoM), todos mapeados aos KPIs correspondentes em
`docs/regras-de-negocio.md`.

---

## 5. Montar os visuais da apresentação

| Slide | Como montar |
|---|---|
| Vendas por Mês | Gráfico de colunas: eixo `dim_calendario[mes_abrev]`, valor `[VGV Bruto]`, com filtro de Ano |
| Vendas Acumuladas (YTD) | Gráfico de linha: eixo `dim_calendario[data]`, valor `[VGV Bruto YTD]` |
| Vendas por Empreendimento | Gráfico de barras: eixo `fato_reservas[empreendimento_conformado]`, valor `[VGV Bruto]` |
| Vendas por Mídia | Gráfico de barras sobre a fato: eixo `fato_reservas[midia]`, valor `[VGV Bruto]`, com slicer de `ano_mes_venda` |
| Ranking de Corretores | Tabela sobre a fato: eixo `fato_reservas[corretor]`, valores `[VGV Bruto]` e `[QTD]`, filtrando House RPO pela classificação oficial, ordenado por VGV decrescente |
| Ranking de Gerentes | Tabela sobre a fato: eixo `fato_reservas[gerente_responsavel]`, valor `[VGV Bruto]`, filtrando House pela classificação oficial, ordenado por VGV decrescente |
| House RPO (slides 6 a 11) | Os mesmos visuais construídos sobre a fato, com o filtro de House/RPO vindo da classificação oficial |

> A regra de House/Parcerias, assim como a de origem, canal e mídia, vem sempre
> da classificação oficial (a Vendas Consolidadas), mesclada por proposta dentro
> do Power BI, nunca de uma coluna direta da fato. Alguns campos extras já vêm
> prontos na fato: `cf_tipo_venda`, `cf_modalidade_financiamento`,
> `cf_motivo_distrato` e `gerente_responsavel`. A exclusão de corretores de
> coordenação (que antes ficava na tabela `ranking_corretores`) agora vira um
> filtro no próprio visual, aplicado através da seed
> `silver.dpara_corretor_fora_ranking`.

### A página "Esteira de vendas" (o funil de reservas)

Monte esse funil diretamente sobre `fato_reservas`, usando as colunas
`situacao_tratada` e `situacao_ordem`, que já vêm prontas na fato:

1. **Ordene a situação corretamente:** selecione a coluna `situacao_tratada`, vá
   em Ferramentas de Coluna → Classificar por coluna → escolha
   `situacao_ordem`. Isso garante que o funil apareça na ordem certa do
   processo, e não em ordem alfabética.
2. **Funil de etapas** (usando o visual Funil, ou um gráfico de colunas):
   categoria `situacao_tratada`, valor `Contagem de id_reserva` (ou, se
   preferir, `[VGV Bruto]`).
3. **Tabela de esteira por gerente** (usando o visual Matriz): linhas
   `gerente_responsavel`, colunas `situacao_tratada`, valores como contagem de
   reservas. É a versão nova da "esteira por gerente" que já existia no BI
   legado.
4. **Segmentações (slicers):** `regional`, `empreendimento_conformado` e
   `ano_mes_venda` (o House/Parcerias e o share continuam vindo da classificação
   oficial).
5. **Para ver só o pipeline em aberto**, filtre por `situacao_ordem <= 13`
   (excluindo Vendida, Cancelada e Distrato). Uma observação: a situação
   "Vencida" (código 12) representa uma reserva expirada; use
   `situacao_ordem <= 11` se quiser enxergar só o funil realmente ativo.

### A página "Pré Cadastro" (o funil de crédito)

É a reimplementação da página "Pré Cadastro" do BI Matriz legado, que tinha 35
visuais, todos decifrados a partir de `_bi_ref/matriz_report.json` e
`matriz_model.bim`. A fonte é `fato_precadastros` (esse schema foi montado em 24
de julho de 2026; veja `MEDIDAS_PRECADASTROS.dax` para as medidas e as notas
sobre a regra DP-05, a esteira e a equipe).

**Antes de montar os visuais**, clique em Atualizar dentro do Desktop: a
`fato_precadastros` ganhou colunas novas (`etapa_bi`, `etapa_bi_detalhada`,
`situacao_anterior`, `situacao_reserva`, `id_reserva`, `eh_venda_reserva`,
`eh_distrato_reserva`, `aprovacao_credito`, `encaminhado_cca`), e o Desktop só
popula essas colunas quando reprocessa o mashup pelo botão Atualizar, não em um
refresh comum via API ou TOM. Depois disso, cole as medidas de
`MEDIDAS_PRECADASTROS.dax` na tabela `Medidas` (dentro da pasta "Pré-Cadastro")
antes de começar a montar os visuais.

| Visual (nome usado no legado) | Tipo | Como montar aqui |
|---|---|---|
| Pastas Imobiliária | Barras | eixo `fato_precadastros[imobiliaria]`, valor `[Qtd Pastas]` |
| Pastas House/Parcerias | Rosca | eixo `depara_corretor_headcount[house_parcerias]`, valor `[Qtd Pastas]` |
| Cadastro por Etapa | Colunas | eixo `fato_precadastros[etapa_bi_detalhada]` (ordenar por texto, já vem numerado de "0." a "6."), valor `[Qtd Pastas]` |
| Pastas Gerentes House | Barras | eixo `depara_corretor_headcount[supervisor]`, valor `[Qtd Pastas]`, com filtro `house_parcerias="House"` |
| Pastas Corretor | Barras | eixo `fato_precadastros[corretor_tratado]`, valor `[Qtd Pastas]` |
| Cadastro por Produto | Colunas agrupadas | eixo `fato_precadastros[empreendimento_conformado]`, valor `[Qtd Pastas]` |
| Analítico dos Leads, Pastas e Reservas | Tabela | colunas `data_cad`, `corretor_tratado`, `id_lead`, `situacao`, `etapa_bi_detalhada`, `empreendimento_conformado`, `imobiliaria`, `id_reserva` |
| Cards do topo | HTML Content | medida `[KPIs Pré-Cadastro HTML]`, com 6 cards (Pastas, Avaliado, Tx Avaliação, Aprovado, Tx Aprovação, Vendas), no mesmo padrão visual do `KPIs Leads HTML` |
| Funil Pastas → Crédito Analisado → Crédito Aprovado → Venda | HTML Content | medida `[Funil Pré-Cadastro HTML]`, no mesmo padrão visual do `Funil Comercial HTML`, só que com 4 estágios em vez de 3 (não é um visual nativo do legado; foi adaptado) |
| Slicers | Segmentação | `fato_precadastros[imobiliaria]`, `fato_precadastros[empreendimento_conformado]`, `depara_corretor_headcount[supervisor]` (rotulado como Equipe Corretor), `depara_corretor_headcount[regional]`, e `dim_calendario` (Ano, Mês, Dia, marcando a hierarquia) |
| Aprovação de Crédito | Rosca | eixo `fato_precadastros[aprovacao_credito]`, valor `[Qtd Pastas]` (ou `COUNTROWS`). Uma cobertura baixa é esperada aqui, cerca de 9%, já que só cobre as pastas efetivamente tocadas pelo time de crédito |
| Encaminhado ao CCA | Rosca | eixo `fato_precadastros[encaminhado_cca]`, valor `[Qtd Pastas]` (ou `COUNTROWS`). A mesma ressalva de cobertura baixa se aplica aqui |

> Os dois gráficos de rosca acima vêm de `silver.precadastros_credito_manual`
> (uma tabela nova, criada em 24 de julho de 2026), carregada a partir do export
> "Relatório Web" do CVCRM (`relatorios_precadastro.xlsx`), através do comando
> `popular_seeds.py --credito-manual`. A API do CVDW não traz essas duas colunas.

**Resolvido em setembro de 2026** (era a única pendência de fonte de dados desta
página): "Pastas por Corretor (House)" comparando com o headcount mensal. A série
mensal do headcount agora existe, como DP-16
(`silver.dpara_corretor_headcount_mensal` e `gold.fato_headcount_mensal`), com
loader no `popular_seeds.py`. Para montar a linha de comparação, use `[Qtd
Pastas]` contra `[Corretores Ativos]`, ou `[Pasta/Mês]` se a leitura desejada for
a média por corretor. As duas medidas estão em `MEDIDAS_PERFORMANCE.dax`.

---

### A página "Performance" (produtividade do corretor e farol de vendas)

É a reimplementação da página "Performance" do BI Matriz legado: a matriz de
corretores com as métricas de esteira mês a mês, o farol de recência de venda e a
matriz de vendas por gerente. As medidas estão em
[`MEDIDAS_PERFORMANCE.dax`](MEDIDAS_PERFORMANCE.dax), e o passo a passo completo
da montagem, com os campos de cada visual e as diferenças deliberadas em relação
ao legado, está em [`PAGINA_PERFORMANCE.md`](PAGINA_PERFORMANCE.md).

Dois pontos que costumam gerar dúvida ao montar:

1. As linhas da matriz vêm de `dim_corretor_headcount`, não da fato. Corretor que
   não vendeu no mês precisa continuar aparecendo, porque é exatamente ele que o
   farol existe para mostrar.
2. `fato_headcount_mensal` se relaciona apenas com `dim_corretor_headcount`, por
   `corretor_chave`. Não crie relacionamento dela com `dim_calendario`: a ponte de
   tempo é feita por `TREATAS` dentro da medida `[Meses Ativos]`.

---

### A página "Atendimento (CVCRM)" (protocolo/ticket de pós-venda)

Sobre `gold.fato_atendimentos_cvcrm`, o endpoint `atendimentos` do CVDW (DP-17
em `docs/regras-de-negocio.md`). **Não confundir com a página "Atendimento" já
existente, que é o chat de WhatsApp via Blip**, os dois fatos e as duas
famílias de medidas levam o mesmo nome de assunto de propósito, mas são
domínios diferentes, sem relação entre si hoje; daí o sufixo `_cvcrm` em tudo
que é novo aqui. As medidas estão em
[`MEDIDAS_ATENDIMENTO_CVCRM.dax`](MEDIDAS_ATENDIMENTO_CVCRM.dax), e o layout
(enxuto de propósito, porque o volume ainda é muito baixo) está em
[`PAGINA_ATENDIMENTO_CVCRM.md`](PAGINA_ATENDIMENTO_CVCRM.md).

---

### As páginas "Repasses" e "Comissões" (módulos do CVCRM)

Duas páginas novas, em HTML e CSS no mesmo design system das outras, sobre os fatos de comissão e repasse da
gold (as tabelas são novas e entram pela interface do Desktop, nunca por XMLA). As medidas estão em
[`MEDIDAS_REPASSES.dax`](MEDIDAS_REPASSES.dax) e [`MEDIDAS_COMISSOES.dax`](MEDIDAS_COMISSOES.dax), e o roteiro
completo (relacionamentos, visuais, campos e números para conferir) está em
[`PAGINA_REPASSES.md`](PAGINA_REPASSES.md) e [`PAGINA_COMISSOES.md`](PAGINA_COMISSOES.md). A análise por trás
dos números e as armadilhas dos dados estão em [`docs/comissoes-e-repasses.md`](../docs/comissoes-e-repasses.md).
Dois avisos: a comissão finalizada **não** é paga (o CVCRM não registra pagamento efetivo), e 85% dos repasses
em andamento são esperas por desenho, que as medidas separam da fila de trabalho.

---

## 6. Validação: como confiar nos números

Antes de apresentar, confira os visuais contra os relatórios já reconciliados em
`reconciliacao/`:
- Ranking de corretores da House RP (maio de 2026): deve trazer Alessandra,
  Rafael e Wallace, na mesma ordem que aparece no visual montado sobre a fato.
- Ranking de gerentes (maio de 2026): Matheus Santamaria deve aparecer com 6
  unidades e R$ 1,75 milhão, batendo com o slide "Liga das vendas".
- Distratos e VGV já estão reconciliados: ao centavo, no caso dos distratos, e em
  98,8% dos casos, no caso do VGV.

> **Atenção:** um banco local costuma ter só uma carga parcial. Para o relatório de verdade,
> use o banco de produção, na máquina Windows descrita em [`infra/README.md`](../infra/README.md).
> Dentro dela, o servidor da conexão é `localhost:5432`; pelo túnel SSH do seu notebook, é
> `localhost:5433`. O usuário é `pafil_bi`, e a senha dele fica no arquivo de credenciais da
> própria máquina de produção. O modelo e as medidas não mudam nesse processo.

## 7. Como atualizar mês a mês

Depois de rodar a carga incremental (`ingestao.py --incremental`) seguida de
`aplicar_tudo.py`, basta clicar em Atualizar dentro do Power BI Desktop. Em
produção, isso já roda sozinho: a máquina Windows física/local
(`infra/README.md`) tem uma tarefa agendada rodando a ingestão
incremental de hora em hora, e o Power BI Service atualiza automaticamente
através do On-premises Data Gateway instalado na mesma máquina do banco.
