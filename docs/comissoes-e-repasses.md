# Comissão e Repasse: dois módulos do CVCRM na plataforma de dados

Levantamento feito em 06/nov/2026, com a produção como fonte. Este documento reúne o que foi
descoberto na API do CVCRM, como os dois módulos entraram no caminho bronze, silver e gold, o que os
números mostram e o que precisa de decisão. Os números citados são desse dia e mudam a cada carga.

## 1. O que foi entregue

| Camada | O que entrou |
|---|---|
| Varredura da API | O catálogo CVDW inteiro (79 endpoints) lido e contado ao vivo: [`cvcrm-api-inventario.md`](cvcrm-api-inventario.md), regerável com `python -m ferramentas.inventariar_cvdw` |
| Bronze | 8 objetos novos (cronograma da comissão, tempo da comissão, repasse, histórico e tempo do repasse, e as 3 definições de workflow), mais o espelho nos 3 objetos de comissão que já existiam |
| Silver | 11 views em [`sql/silver/comissoes_repasses.sql`](../sql/silver/comissoes_repasses.sql) |
| Gold | 5 objetos de repasse e 6 de comissão em [`sql/gold/comissoes_repasses.sql`](../sql/gold/comissoes_repasses.sql) |
| Pipeline | Duas opções novas no `config/objetos.yml`: `base` e `espelho` (seção 5) |
| Power BI | 80 medidas (21 que devolvem HTML e 4 de CSS), em [`MEDIDAS_REPASSES.dax`](../powerbi/MEDIDAS_REPASSES.dax) e [`MEDIDAS_COMISSOES.dax`](../powerbi/MEDIDAS_COMISSOES.dax), com o roteiro das duas páginas em [`PAGINA_REPASSES.md`](../powerbi/PAGINA_REPASSES.md) e [`PAGINA_COMISSOES.md`](../powerbi/PAGINA_COMISSOES.md) |

O que já está na produção (aplicado do notebook em 06/nov/2026, pelo túnel, como `pafil_app`): as 16
tabelas novas da bronze (8 mais os 8 snapshots diários) com carga completa (92.927 linhas nas 8
principais), as 11 views da silver e os 11 objetos da
gold. O que falta é a VM ler o código novo (seção 9).

## 2. Os dois módulos, em português

**Repasse.** É a etapa em que o financiamento bancário do comprador (Caixa, por meio de um
correspondente) é contratado, registrado e liberado para a construtora. Cada venda a financiar tem um
repasse, que percorre um workflow de 35 etapas (documentação, conformidade, entrevista, minuta,
assinatura, ITBI, cartório, liberação de recursos) até "Repasse Finalizado". Pode terminar de quatro
jeitos: finalizado, cancelado, distrato ou cessão de direitos. É 1:1 com a reserva.

**Comissão.** A reserva tem *regras* de comissão (quem recebe, quanto, de que tipo). Na venda o CVCRM
gera a *comissão*, o total devido, que percorre um workflow de sete situações e se desdobra em
*pagamentos* (parcelas com vencimento). O *cronograma* previsto é a programação de cada regra, desde a
venda. Quando a regra muda, o CVCRM cancela a comissão e gera outra: uma reserva pode ter várias, e só
a não cancelada vale.

## 3. Varredura da API do CVCRM

A varredura partiu do índice oficial do portal do desenvolvedor (`llms.txt`) e da página de cada
referência, e não de caminhos chutados. Um caminho inventado que responde HTTP 405 não prova que o dado
não existe: `correspondentes/empresas` deu 405 e o caminho certo é `correspondentes-empresas`, com
hífen. O resultado completo, com contagem ao vivo e campos de cada endpoint, está em
[`cvcrm-api-inventario.md`](cvcrm-api-inventario.md).

Endpoints dos dois módulos no CVDW (autenticação por e-mail e token, a mesma da ingestão):

| Endpoint | Registros | Situação |
|---|---:|---|
| `comissoes` | 3.891 | já ingerido, agora com espelho |
| `comissoes/pagamentos` | 4.410 | já ingerido, agora com espelho (209 linhas fantasma removidas) |
| `reservas/comissoes` (regras) | 10.489 | já ingerido, agora com espelho |
| `comissoes/workflow/tempo` | 8.411 | novo |
| `reservas/comissoes/programacao` (cronograma) | 18.129 | novo, com espelho |
| `repasses` | 3.440 | novo, com espelho |
| `repasses/historico/situacoes` | 31.782 | novo |
| `repasses/workflow/tempo` | 31.112 | novo |
| `correspondentes-empresas` | 7 | avaliado e não ingerido: o nome da empresa já vem no repasse |
| `correspondentes-usuarios` | 30 | avaliado e não ingerido: é só dado pessoal (CPF, e-mail) e nenhuma análise precisa dele |

As definições de workflow não são do CVDW: vêm de `GET /api/v1/configuracoes/workflows/{funcionalidade}`
(`repasses`, `comissoes`, `situacao_pagamento_comissao`). Elas dizem a ordem das etapas e quais
encerram o processo (flags `fim`, `cancelado`, `distrato`, `cessao`), então nenhuma regra de "o que é
finalizado" ficou escrita à mão no SQL.

**Fora do CVDW** existem rotas operacionais (v1 e v3) que não entraram, e vale saber por quê:

- `GET /v1/financeiro/repasses` (HTTP 200): traz campos que o CVDW não tem (`sla_prazo_repasse`,
  `porcentagem_medicao_obra`, correspondente e agência), mas devolve nome, telefone, e-mail e
  nascimento do cliente e as mensagens do repasse em HTML (18 KB por registro). Não compensa.
- `GET /v1/financeiro/comissoes` (HTTP 200): traz o desdobramento em prêmio, `data_finalizacao` e
  `data_pago`, mas também o cadastro completo do pagador. A data de finalização já se obtém do workflow.
- `GET /v1/financeiro/comissoes/parcelas` e `GET /v1/financeiro/lotes/{id}` (HTTP 403): o usuário da
  API não tem permissão. Se um dia for preciso saber o pagamento efetivo, é aqui que ele mora, e o
  caminho é pedir a permissão ao administrador do CVCRM.
- `GET /v3/financeiro/repasses/numeros`: exige Bearer (login com senha); não testado.

**A referência diverge do servidor**, como no resto do projeto: o repasse manda `data_modificao` (sem o
"c") e traz `ultima_atualizacao` e `data_modificao_situacao`; o campo `reserva` vem sempre 0 (o
identificador é `idreserva`); `data_pagamento` da comissão é a data programada, e não a efetiva.

## 4. O caminho do dado

```
CVDW (API) ──ingestao.py──> bronze.* ──views──> silver.* ──views──> gold.* ──> Power BI
```

### Bronze (`sql/bronze/bronze.sql`, DDL escrito à mão a partir de amostra ao vivo)

| Tabela | Grão | Chave do upsert | Carga |
|---|---|---|---|
| `repasses` | 1 repasse | `idrepasse` | incremental e espelho diário |
| `repasses_historico_situacoes` | 1 mudança de situação | `idhistorico` | incremental |
| `repasses_workflow_tempo` | 1 passagem por etapa | `idtempo` | incremental |
| `comissoes_workflow_tempo` | 1 passagem por situação | `idtempo` | incremental |
| `reservas_comissoes_programacao` | 1 parcela prevista | `idprogramacao` | incremental e espelho diário |
| `workflows_repasses`, `workflows_comissoes`, `workflows_comissoes_pagamentos` | 1 situação | `idsituacao` | lidas inteiras a cada execução |

Cada tabela tem a gêmea `_snapshot` (cópia diária). Antes de fechar o DDL, os tipos foram conferidos
contra todos os registros da API: só `comissoes_pagamentos.unidade` perdia dado (R29).

### Silver (`sql/silver/comissoes_repasses.sql`)

| View | Grão | O que faz |
|---|---|---|
| `repasses_situacoes` | 1 etapa (50) | as 35 etapas do workflow mais as 15 aposentadas, com a **fase** de negócio (proposta de agrupamento, editável na própria view) |
| `repasses` | 1 repasse | tipagem, flags de fim, dinheiro e os campos adicionais mais recentes (modalidade, tipo de venda, FGTS) |
| `repasses_historico`, `repasses_workflow_tempo` | 1 evento | nomes de negócio, tempo em minutos |
| `comissoes_situacoes`, `comissoes_pagamentos_situacoes` | 1 situação | ordem, flags e o grupo do funil |
| `comissoes`, `comissoes_pagamentos`, `comissoes_workflow_tempo` | 1 comissão, pagamento ou passagem | sem nome e CEP do cliente |
| `comissoes_regras`, `comissoes_programacao` | 1 regra, 1 parcela | códigos do CVCRM decodificados (IC, IR, CR, UA e outros) |

A função `silver.campo_adicional_atual` devolve a entrada **mais recente** de um campo customizado (R28).

### Gold (`sql/gold/comissoes_repasses.sql`)

Desenho galaxy, como o resto do modelo: cada fato liga direto nas dimensões compartilhadas e **não**
liga em outro fato. Por isso os fatos filhos repetem as chaves de corte.

| Objeto | Grão | Para quê |
|---|---|---|
| `dim_repasse_etapa` | 1 etapa | ordem de exibição, fase, flags (espera, pendência) |
| `dim_correspondente` | 1 correspondente | corte por correspondente |
| `fato_repasses` | 1 repasse | status, `condicao_andamento` (em tratativa x em espera x encerrado), aging, ciclo, lotes, valores |
| `fato_repasses_etapas` | 1 passagem por etapa | tempo por etapa (mediana e p90) |
| `fato_repasses_movimentos` | 1 mudança de situação | finalizações por mês, retrabalho, quem moveu |
| `dim_comissao_situacao` | 1 situação | funil de comissão |
| `dim_imobiliaria` | 1 imobiliária | House ou Parcerias (de `silver.dpara_imobiliaria_house`) |
| `fato_comissoes` | 1 comissão | status, valor devido, aging, reserva sem venda |
| `fato_comissoes_pagamentos` | 1 pagamento | obrigações e faixa de vencimento |
| `fato_comissoes_programacao` | 1 parcela prevista | previsão de caixa |
| `fato_comissoes_regras` | 1 regra | quem recebe, em % do contrato |

## 5. Duas mudanças no pipeline

**`base`.** As definições de workflow ficam em outro grupo da API (`/api/v1/configuracoes/...`, e não
`/api/v1/cvdw/...`). O `config/objetos.yml` ganhou o campo opcional `base` (padrão `cvdw`), e
`ClienteCVDW` passou a aceitá-lo. Nada muda para os objetos que já existiam.

**`espelho`.** A bronze só fazia upsert: o que o CVCRM apaga ficava para sempre. Cancelar uma comissão
remove os pagamentos dela, e editar as regras de uma reserva refaz o cronograma. Em 06/nov/2026 a
origem tinha 4.410 pagamentos e a bronze 4.619: **209 linhas fantasma (R$ 582 mil)**, que entrariam no
fluxo de caixa. Com `espelho: true` o objeto é lido inteiro uma vez por dia (`CVDW_ESPELHO_HORAS`, 20 h)
e em todo `--full`, e o que a origem não devolve é apagado da bronze. Quatro proteções:

1. **A leitura precisa fechar com o total que a origem declara.** A paginação do CVDW ordena só por
   data de modificação e, quando muitos registros têm a mesma data (carga em lote), repete uns e pula
   outros na fronteira entre páginas, **sempre os mesmos para o mesmo tamanho de página** (R32). Por isso
   a leitura conta os ids distintos e compara com o `total_de_registros`; se faltar, relê com 400, 450 e
   350 por página e soma. Só uma leitura que fecha libera a limpeza; se nenhuma fechar, nada é removido
   e a nova tentativa fica para daqui a 20 h.
2. Só se apaga o que ficou de fora de **duas leituras completas seguidas** (segunda camada, para um
   registro criado ou apagado no meio da leitura).
3. Trava de 25% da tabela (mínimo de 50 linhas): se a limpeza apagaria mais que isso, o objeto falha e
   a bronze fica como estava. Se a origem devolver zero registros, nada é apagado.
4. Os snapshots diários não são tocados: o histórico do que já existiu continua lá.

Testado num schema temporário com uma cópia real: a 2ª leitura removeu exatamente as 209 linhas, e com
1.500 linhas plantadas a trava abortou. A conferência da proteção 1 foi testada com uma cópia do
`repasses` mais um fantasma: a leitura de 500 por página trouxe 3.434 ids de 3.440, a releitura de 400
completou, o fantasma saiu e os 6 repasses recuperados ficaram. Em produção, o espelho foi ativado nos
objetos de comissão e removeu as mesmas 209 linhas. A coluna nova `ultima_leitura_completa` da tabela
`bronze._ingestao_controle` é criada sozinha na primeira execução.

## 6. O que os dados dizem

### Repasse

1. **A fila de trabalho é pequena, e a "fila" que se vê é espera.** Dos 521 repasses em andamento,
   **445 (85%) estão em Aguardando APF ou Finan. Chaves**, esperas por desenho que só andam quando um
   marco externo acontece (APF nas Villas, entrega das chaves nos demais). A fila real são os **76 em
   tratativa (R$ 19,3 mi de VGV)**, e só **18 deles estão há mais de 30 dias** na mesma etapa. As
   esperas valem R$ 145 mi de VGV e têm 652 dias de média na etapa.
2. **Conversão de 56%.** Dos 2.919 repasses que chegaram a um fim, 1.635 finalizaram. O resto foi
   distrato (755), cancelamento (524) e cessão (5). Varia muito por correspondente (REM 64%, Finance 63%,
   RM Assessoria 47%, Innova 49%) e por empreendimento (Parc Sul Residence 94%, Villas do Parque 47%).
3. **Retrabalho em 55% dos finalizados.** 902 dos 1.635 passaram ao menos uma vez por uma etapa de
   pendência, e 271 passaram 6 vezes ou mais. As etapas que mais voltam são Atualização Documental,
   Conferência | Reavaliar, Divergência e Pendência.
4. **Onde o repasse demora** (mediana em dias, p90 entre parênteses): Recolhimento | ITBI 13,8 (89),
   Prenotado | Cartório 11,2 (32), Emissão de Minuta 9,1 (77), Pendência 7,1 (60). ITBI e cartório somam
   cerca de 30 dias de mediana.
5. **Ciclo.** Mediana de 97 dias para quem abriu em 2025 e 76 para 2026 (este ainda incompleto, porque só
   entra quem já finalizou). Os repasses de 2024 mostram 389 dias, mas é uma coorte contaminada por lote.
6. **Distrato depois do dinheiro.** 18 repasses finalizaram (o banco pagou) e depois viraram distrato ou
   cancelamento.
7. **Vendas a financiar sem repasse.** 71 vendas estão sem repasse, e 26 delas são de financiamento
   (Financiamento na Planta ou Chaves): é a lista que o backoffice precisa abrir.
8. **Quase metade do histórico é carga em lote.** 1.692 repasses (49%) foram abertos em dias com 40 ou
   mais aberturas (427 em 26/fev/2024, 122 na migração de 09/nov/2023) e 1.232 mudaram de situação em
   lote (326 finalizações em 10/abr/2024). Série mensal e ciclo precisam desse filtro (R31).
9. **Quem mexe no repasse.** 40% das mudanças de situação são feitas pelo correspondente, e 60% pela
   equipe da Pafil.

### Comissão

1. **Custo efetivo de 4,9% do VGV.** R$ 20,3 mi de comissão devida sobre R$ 417 mi de VGV. Por ano de
   venda, a House custa 4,4% a 4,8% e Parcerias 5,1% a 5,3%. Mas a House não é uniformemente mais barata:
   o escritório de Ribeirão Preto fica em 4,4% e os de São Carlos e Uberaba em 5,9% e 6,0%, no patamar
   das parceiras (Atlas 5,9%, Correta 5,9%, Nova Aliança 6,0%).
2. **Um terço do gerado é cancelado.** R$ 10,3 mi de R$ 30,7 mi. Quase tudo é distrato: das 813
   comissões de reservas distratadas, 812 foram canceladas. O processo de cancelamento funciona.
3. **Mas ficam 135 comissões vivas em reserva sem venda (R$ 1,84 mi).** São de reservas canceladas,
   vencidas ou distratadas, e 100 delas (R$ 1,33 mi) seguem "Em apuração". É limpeza de cadastro.
4. **Nota fiscal pendente é carteira antiga.** 223 comissões (R$ 2,81 mi) esperam a nota fiscal, e a
   mediana de espera é de 826 dias em "Aguardando NF" e 402 dias nas de corretor desligado (201 comissões,
   R$ 2,47 mi). Vale cobrança ou baixa contábil.
5. **Previsão de caixa concentrada em ago/2027.** O cronograma das reservas vendidas tem R$ 3,8 mi a
   vencer (R$ 109 mil nos próximos 30 dias), dos quais R$ 3,0 mi em 518 parcelas de **agosto de 2027**,
   ligadas à entrega. Já venceram R$ 13,7 mi de cronograma, e o CVCRM não diz se foram pagos.
6. **Quem recebe.** Dos 4,9% do contrato, 4,2% vão para a imobiliária, 0,6% para o corretor, 0,04% para a
   equipe interna da Pafil e 0,02% para usuário da imobiliária (regras ativas das reservas vendidas).
7. **Cascas.** 1.503 das 3.891 comissões têm valor zero (1.264 "Aguardando Apuração", quase todas de 2023
   e 2024): foram criadas na venda e nunca apuradas.

## 7. Armadilhas e decisões

Detalhe e ação de cada uma em [`regras-de-negocio.md`](regras-de-negocio.md), seção 7.

| # | Armadilha | Estado |
|---|---|---|
| R27 | A bronze não apagava o que sumia da origem (209 pagamentos fantasma) | Concluído, espelho |
| R28 | `silver.campo_adicional` devolve a entrada **mais antiga** do histórico de campos customizados: 819 reservas (487 vendidas) com gerente diferente do mais recente | **Precisa de decisão**, seção 10 |
| R29 | `bronze.comissoes_pagamentos.unidade` era numeric e perdia 34% dos valores ("153 - TERRENISTA") | Concluído |
| R30 | Comissão finalizada não é paga: nenhum pagamento está em PAGO, não há data de pagamento efetivo | Atenção, documentado na página |
| R31 | Repasse em andamento é 85% espera, lotes distorcem série e ciclo, valor financiado só vale desde 2025 | Atenção, tratado nas colunas e nas medidas |
| R32 | A paginação do CVDW repete e pula registros de mesma data de modificação (6 repasses reais ficaram de fora da bronze) | Concluído no espelho; atenção nos demais objetos |

## 8. Como conferir

Todos de leitura, rodados da raiz do repositório:

```powershell
.\.venv\Scripts\python.exe conferir_carga.py
.\.venv\Scripts\python.exe aplicar_silver.py --so-comissoes-repasses --validar
.\.venv\Scripts\python.exe aplicar_gold.py --so-comissoes-repasses --validar
```

`conferir_carga.py` compara o total da origem com o da bronze de cada objeto, e o esperado é diferença
zero nos objetos de comissão e repasse. Diferença positiva (origem maior que a bronze) num objeto com
espelho é o sinal da paginação instável (R32): `ingestao.py --full --objetos <objeto>` relê com outro
tamanho de página até fechar com o total. Os objetos mais antigos têm diferenças que já existiam e não
foram tratadas (lista na R27).

## 9. Colocar na VM

A produção já tem os dados e as views, porque foram aplicados do notebook. O que a VM ainda não sabe é
que existem objetos novos: até ela ler o `config/objetos.yml` novo, a carga horária não atualiza as 8
tabelas novas (elas ficam paradas na foto de 06/nov/2026) e o espelho diário não roda. Passo a passo:

1. No notebook, commitar e publicar na branch que a VM acompanha (confira com
   `git branch --show-current` na VM: se ainda for `mdnet-telefonia`, resolva a troca para `master`
   primeiro, como descrito em [`infra/README.md`](../infra/README.md)).
2. Na VM, em `C:\pafil\app`, no PowerShell: `git pull`.
3. Rodar à mão uma vez, para conferir antes da próxima hora cheia:
   `.\.venv\Scripts\python.exe ingestao.py --incremental --objetos repasses,comissoes,comissoes_pagamentos`
   (tem de terminar com 0 falhas).
4. Conferir: `.\.venv\Scripts\python.exe conferir_carga.py` (diferença zero nos objetos de comissão e repasse).
5. Nas 24 horas seguintes o espelho faz a leitura completa dos 8 objetos marcados, conferida contra o
   total da origem, e na segunda leitura que fecha remove o que a origem apagou. O log diz
   `espelho: N linha(s) removida(s)`, ou `espelho: nenhuma leitura fechou com o total da origem` quando
   a conferência não fecha (nada é removido e a nova tentativa fica para daqui a 20 h).

Não é preciso rodar `--criar-tabelas` nem reaplicar silver e gold: já estão na produção, e os scripts
`aplicar_silver.py` e `aplicar_gold.py` são idempotentes, então a próxima aplicação normal os mantém.

## 10. O que ficou de fora e o que pede decisão

- **R28, valor mais antigo dos campos customizados.** O array `campos_adicionais` das reservas guarda o
  histórico de cada campo, e `silver.campo_adicional` devolve a primeira entrada, a mais antiga. Em
  06/nov/2026, 972 reservas tinham "Gerente Responsavel" com mais de um valor, e em 819 a gold mostra o
  valor antigo (487 delas vendidas). Exemplo: a reserva 5745 mostra "Gabriel (Imob URA)" na gold, mas a
  última edição, de 08/set/2026, diz "Alexandre Escolano". **Não alterei** `silver.campo_adicional`
  porque mudaria o ranking por gerente já apresentado. A correção é uma linha (ordenar por
  `idcampo_valores` decrescente, como em `silver.campo_adicional_atual`), e antes dela vale abrir 2 ou 3
  reservas no CVCRM para confirmar que a tela mostra o valor mais recente.
- **Pagamento efetivo da comissão.** Não existe nos dados do CVCRM. Para ter, é preciso a permissão da
  rota de parcelas (HTTP 403 hoje) ou o dado do financeiro (MEGA).
- **Agrupamento das fases do repasse.** As 8 fases são uma proposta (o campo `grupos` do workflow vem
  vazio no CVCRM). Para renomear ou mover uma etapa, edite a lista em `silver.repasses_situacoes`.
- **Quem recebe, por nome.** A comissão por beneficiário usa só o tipo (imobiliária, corretor, equipe
  interna). Resolver o nome de usuário administrativo exigiria ingerir `usuarios_administrativos` (211
  linhas, com dado pessoal).
- **Os dois itens de limpeza** que a página expõe (135 comissões vivas em reserva sem venda; 26 vendas a
  financiar sem repasse) são trabalho do backoffice, e não do pipeline.
