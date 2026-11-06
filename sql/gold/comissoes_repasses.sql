-- Camada GOLD de COMISSÃO e REPASSE (nov/2026): fatos e dimensões para o Power BI, sobre a silver.
-- Aplicar com `python aplicar_gold.py` (entra no fluxo completo, depois de gold.sql) ou, sozinha e
-- sem refazer o resto da gold, com `python aplicar_gold.py --so-comissoes-repasses`.
-- Depende de sql/silver/comissoes_repasses.sql, de silver.reservas e silver.dpara_* e de
-- gold.dim_empreendimento (que nasce em gold.sql). Análise e roteiro das páginas em
-- docs/comissoes-e-repasses.md, powerbi/PAGINA_REPASSES.md e powerbi/PAGINA_COMISSOES.md.
--
-- Desenho (galaxy, como o resto do modelo): cada fato liga direto nas dimensões compartilhadas
-- (dim_calendario, dim_empreendimento, e as novas dim_correspondente e dim_imobiliaria) e NÃO liga
-- em outro fato. Por isso os fatos filhos repetem as chaves que os cortes precisam. Dado pessoal
-- (nome, CPF, CEP e telefone do cliente) não entra em nenhum objeto.
--
-- Objetos:
--   REPASSE   dim_repasse_etapa, dim_correspondente, fato_repasses, fato_repasses_etapas,
--             fato_repasses_movimentos
--   COMISSÃO  dim_comissao_situacao, dim_imobiliaria, fato_comissoes, fato_comissoes_pagamentos,
--             fato_comissoes_programacao, fato_comissoes_regras

CREATE SCHEMA IF NOT EXISTS gold;


-- ===========================================================================
-- DIMENSÕES DE REPASSE
-- ===========================================================================

-- As etapas do workflow de repasses (35 atuais mais as descontinuadas que o histórico ainda cita),
-- com a fase de negócio e uma ordem de exibição única (fase, depois a ordem do workflow). No
-- Power BI, classificar `situacao` por `ordem_exibicao` e `fase` por `fase_ordem`.
CREATE OR REPLACE VIEW gold.dim_repasse_etapa AS
SELECT
    s.id_situacao,
    s.situacao,
    s.ordem,
    s.fase,
    s.fase_ordem,
    row_number() OVER (ORDER BY s.fase_ordem, coalesce(s.ordem, 999), s.id_situacao)::smallint AS ordem_exibicao,
    s.eh_inicio,
    s.eh_fim                  AS eh_finalizado,
    s.eh_cancelado,
    s.eh_distrato,
    s.eh_cessao,
    s.eh_descontinuada,
    (s.fase_ordem = 6)        AS eh_pendencia,   -- a equipe precisa agir
    (s.fase_ordem = 7)        AS eh_espera       -- Aguardando APF e Finan. Chaves: espera por desenho
FROM silver.repasses_situacoes s;


-- Correspondentes bancários que tocam os repasses. Quem não tem correspondente cadastrado fica
-- como 'Sem correspondente' (28% dos repasses, em sua maioria antigos ou de venda direta).
CREATE OR REPLACE VIEW gold.dim_correspondente AS
SELECT DISTINCT coalesce(r.correspondente, 'Sem correspondente') AS correspondente
FROM silver.repasses r;


-- ===========================================================================
-- FATO DE REPASSE. Grão = 1 repasse (id_repasse), 1:1 com a reserva.
--
-- Como ler o andamento. Dos repasses "em andamento", a maioria (85% em 06/nov/2026) está em
-- Aguardando APF ou Finan. Chaves: esperas longas por desenho, em que o repasse só anda quando um
-- marco externo acontece. Por isso há duas colunas: `status_repasse` (o que o CVCRM diz) e
-- `condicao_andamento` (Em tratativa x Em espera por marco x Encerrado), que separa a fila de
-- trabalho real da espera.
--
-- Datas. `data_finalizacao` e `data_encerramento` vêm de data_alteracao_status, que é a data da
-- última mudança de situação: conferido em 06/nov/2026, é igual à data da última transição do
-- histórico em 1.635 dos 1.635 finalizados.
--
-- Cuidado com lotes. O time de repasse fecha e abre repasses em lote (427 aberturas em
-- 26/fev/2024; 326 finalizações em 10/abr/2024), e esses dias distorcem série mensal e ciclo.
-- `eh_abertura_em_lote` e `eh_mudanca_em_lote` marcam repasses que dividiram o dia com 40 ou mais
-- iguais; `eh_ciclo_confiavel` (finalizado, sem lote nas duas pontas) é a base do ciclo.
--
-- Valores. valor_contrato vem em todos; valor_financiado só é confiável a partir de 2025
-- (`tem_valor_financiado`). Os campos de cliente não entram.
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_repasses AS
WITH mov AS (
    SELECT h.id_repasse,
           count(*)                                       AS qtd_movimentos,
           count(*) FILTER (WHERE s.fase_ordem = 6)       AS qtd_passagens_pendencia,
           bool_or(coalesce(s.eh_fim, false))             AS ja_foi_finalizado
    FROM silver.repasses_historico h
    LEFT JOIN silver.repasses_situacoes s ON s.id_situacao = h.id_para
    GROUP BY h.id_repasse
),
base AS (
    SELECT r.*,
           count(*) OVER (PARTITION BY r.data_cad::date)                                AS abertos_no_dia,
           count(*) OVER (PARTITION BY r.data_alteracao_status::date, r.id_situacao)    AS mudancas_no_dia
    FROM silver.repasses r
)
SELECT
    r.id_repasse,
    r.id_reserva,
    r.id_empreendimento,
    r.id_unidade,
    r.id_cliente,

    r.data_cad::date                                          AS data_cad,
    r.data_venda::date                                        AS data_venda,
    CASE WHEN r.eh_finalizado THEN r.data_alteracao_status::date END AS data_finalizacao,
    CASE WHEN r.eh_encerrado  THEN r.data_alteracao_status::date END AS data_encerramento,
    r.data_alteracao_status::date                             AS data_ultima_mudanca,

    r.empreendimento,
    silver.conformar_empreendimento(r.empreendimento)         AS empreendimento_conformado,
    r.etapa, r.bloco, r.unidade,
    coalesce(r.correspondente, 'Sem correspondente')          AS correspondente,
    r.modalidade_financiamento,
    r.tipo_venda_repasse,
    r.utiliza_fgts,
    r.aprovacao_credito,
    r.situacao_contrato,

    r.id_situacao,
    r.situacao,
    r.ordem_etapa,
    r.fase,
    r.fase_ordem,
    CASE WHEN r.eh_finalizado THEN 'Finalizado'
         WHEN r.eh_distrato   THEN 'Distrato'
         WHEN r.eh_cancelado  THEN 'Cancelado'
         WHEN r.eh_cessao     THEN 'Cessão de direitos'
         ELSE 'Em andamento' END                              AS status_repasse,
    CASE WHEN r.eh_finalizado THEN 2
         WHEN r.eh_cancelado  THEN 3
         WHEN r.eh_distrato   THEN 4
         WHEN r.eh_cessao     THEN 5
         ELSE 1 END::smallint                                 AS status_repasse_ordem,
    CASE WHEN r.eh_encerrado     THEN 'Encerrado'
         WHEN r.fase_ordem = 7   THEN 'Em espera por marco'
         ELSE 'Em tratativa' END                              AS condicao_andamento,
    r.eh_finalizado,
    r.eh_encerrado,
    (NOT r.eh_encerrado)                                      AS eh_em_andamento,
    (NOT r.eh_encerrado AND r.fase_ordem = 7)                 AS eh_em_espera,
    (NOT r.eh_encerrado AND r.fase_ordem = 6)                 AS eh_em_pendencia,
    (r.eh_cancelado OR r.eh_distrato OR r.eh_cessao)          AS eh_encerrado_sem_repasse,
    coalesce(m.ja_foi_finalizado, false)                      AS ja_foi_finalizado,
    -- finalizou (o dinheiro entrou) e depois virou distrato ou cancelamento
    (coalesce(m.ja_foi_finalizado, false) AND NOT r.eh_finalizado
        AND (r.eh_distrato OR r.eh_cancelado))                AS eh_distrato_pos_repasse,

    -- Tempo parado na etapa atual, só para quem está em andamento. Esperas por desenho (fase 7)
    -- também têm a coluna, mas o Power BI as trata à parte.
    CASE WHEN NOT r.eh_encerrado
         THEN (current_date - r.data_alteracao_status::date) END::int AS dias_na_etapa,
    CASE WHEN r.eh_encerrado THEN NULL
         WHEN current_date - r.data_alteracao_status::date <= 7   THEN '1 - Até 7 dias'
         WHEN current_date - r.data_alteracao_status::date <= 30  THEN '2 - 8 a 30 dias'
         WHEN current_date - r.data_alteracao_status::date <= 90  THEN '3 - 31 a 90 dias'
         WHEN current_date - r.data_alteracao_status::date <= 180 THEN '4 - 91 a 180 dias'
         ELSE '5 - Mais de 180 dias' END                      AS faixa_dias_na_etapa,
    CASE WHEN NOT r.eh_encerrado THEN (current_date - r.data_cad::date) END::int AS dias_desde_abertura,
    CASE WHEN r.data_cad::date >= r.data_venda::date
         THEN (r.data_cad::date - r.data_venda::date) END::int AS dias_venda_ate_abertura,
    CASE WHEN r.eh_finalizado
         THEN (r.data_alteracao_status::date - r.data_cad::date) END::int AS dias_ciclo,
    (r.abertos_no_dia >= 40)                                  AS eh_abertura_em_lote,
    (r.mudancas_no_dia >= 40)                                 AS eh_mudanca_em_lote,
    (r.eh_finalizado AND r.abertos_no_dia < 40 AND r.mudancas_no_dia < 40
        AND r.data_alteracao_status::date >= r.data_cad::date) AS eh_ciclo_confiavel,

    coalesce(m.qtd_movimentos, 0)::int                        AS qtd_movimentos,
    coalesce(m.qtd_passagens_pendencia, 0)::int               AS qtd_passagens_pendencia,

    r.valor_contrato,
    r.valor_financiado,
    r.valor_divida,
    r.valor_subsidio,
    r.valor_fgts,
    r.valor_previsto,
    r.tem_valor_financiado,
    CASE WHEN r.tem_valor_financiado AND r.valor_contrato > 0
         THEN round(100 * r.valor_financiado / r.valor_contrato, 2) END AS pct_financiado,

    rv.situacao                                               AS situacao_reserva,
    rv.imobiliaria,
    silver.chave_nome(rv.corretor)                            AS corretor_chave,
    coalesce(ih.house_parcerias, 'Parcerias')                 AS house_parcerias,
    de.regional,
    r.ano_cad,
    r.ano_mes_cad
FROM base r
LEFT JOIN mov m                      ON m.id_repasse = r.id_repasse
LEFT JOIN silver.reservas rv         ON rv.id_reserva = r.id_reserva
LEFT JOIN silver.dpara_imobiliaria_house ih ON ih.imobiliaria = rv.imobiliaria
LEFT JOIN gold.dim_empreendimento de ON de.id_empreendimento = r.id_empreendimento;


-- ===========================================================================
-- REPASSE: tempo por etapa. Grão = 1 passagem do repasse por uma etapa. `tempo_dias` é o tempo na
-- etapa e `data_saida` o dia em que saiu dela (a etapa atual ainda não tem linha). Repete as chaves
-- de corte do repasse (empreendimento, correspondente) para ligar direto nas dimensões. `eh_espera`
-- separa Aguardando APF e Finan. Chaves, que têm mediana de 4 a 5 meses e esmagariam o gráfico.
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_repasses_etapas AS
SELECT
    w.id_tempo,
    w.id_repasse,
    w.id_situacao,
    coalesce(e.situacao, w.situacao)                          AS situacao,
    coalesce(e.fase, '9. Outras etapas')                      AS fase,
    coalesce(e.fase_ordem, 9)::smallint                       AS fase_ordem,
    e.ordem_exibicao,
    coalesce(e.eh_espera, false)                              AS eh_espera,
    coalesce(e.eh_pendencia, false)                           AS eh_pendencia,
    coalesce(e.eh_descontinuada, false)                       AS eh_descontinuada,
    w.tempo_min,
    round(w.tempo_min / 1440.0, 2)                            AS tempo_dias,
    w.data_saida::date                                        AS data_saida,
    f.id_empreendimento,
    f.correspondente,
    f.status_repasse
FROM silver.repasses_workflow_tempo w
JOIN gold.fato_repasses f           ON f.id_repasse = w.id_repasse
LEFT JOIN gold.dim_repasse_etapa e  ON e.id_situacao = w.id_situacao;


-- ===========================================================================
-- REPASSE: movimentações. Grão = 1 mudança de situação (id_historico). Mostra quem moveu o repasse
-- (equipe interna ou correspondente) e quando, e sustenta a série de finalizações por mês, o
-- retrabalho (voltas para etapas de pendência) e a produtividade. `usuario` é nome de funcionário
-- (vazio quando quem mexeu foi o correspondente): use para visão de equipe, não de pessoa.
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_repasses_movimentos AS
SELECT
    h.id_historico,
    h.id_repasse,
    h.data_movimento::date                                    AS data_movimento,
    h.id_de,
    h.situacao_de,
    h.id_para,
    coalesce(p.situacao, h.situacao_para)                     AS situacao_para,
    coalesce(p.fase, '9. Outras etapas')                      AS fase_para,
    coalesce(p.fase_ordem, 9)::smallint                       AS fase_para_ordem,
    coalesce(p.eh_fim, false)                                 AS eh_finalizacao,
    (coalesce(p.fase_ordem, 9) = 6)                           AS eh_retrabalho,
    h.usuario,
    h.eh_correspondente,
    CASE WHEN h.eh_correspondente THEN 'Correspondente' ELSE 'Equipe Pafil' END AS quem_moveu,
    f.id_empreendimento,
    f.correspondente
FROM silver.repasses_historico h
JOIN gold.fato_repasses f           ON f.id_repasse = h.id_repasse
LEFT JOIN silver.repasses_situacoes p ON p.id_situacao = h.id_para;


-- ===========================================================================
-- DIMENSÕES DE COMISSÃO
-- ===========================================================================

-- As situações da comissão e o grupo do funil.
CREATE OR REPLACE VIEW gold.dim_comissao_situacao AS
SELECT
    s.id_situacao, s.situacao, s.ordem, s.grupo, s.grupo_ordem,
    s.eh_inicio, s.eh_fim AS eh_finalizada, s.eh_cancelada
FROM silver.comissoes_situacoes s;


-- Imobiliárias com a classificação House ou Parcerias (a que a Vendas Consolidadas usa: os escritórios
-- próprios da Pafil são House, o resto é Parcerias). O nome é a chave, porque comissão e reserva só
-- trazem o nome. Variante de grafia entra como linha nova em silver.dpara_imobiliaria_house.
CREATE OR REPLACE VIEW gold.dim_imobiliaria AS
SELECT
    x.imobiliaria,
    coalesce(ih.house_parcerias, 'Parcerias')                 AS house_parcerias,
    ih.regional                                               AS regional_house,
    ih.share                                                  AS share_house
FROM (
    SELECT imobiliaria FROM silver.reservas  WHERE imobiliaria IS NOT NULL
    UNION
    SELECT imobiliaria FROM silver.comissoes WHERE imobiliaria IS NOT NULL
) x
LEFT JOIN silver.dpara_imobiliaria_house ih ON ih.imobiliaria = x.imobiliaria;


-- ===========================================================================
-- FATO DE COMISSÃO. Grão = 1 comissão (id_comissao). Uma reserva pode ter várias (o CVCRM cancela a
-- antiga e gera outra quando a regra muda); só conta a que não está cancelada.
--
-- Três avisos que vêm dos dados (06/nov/2026), explicados em docs/comissoes-e-repasses.md:
--  1. FINALIZADA NÃO É PAGA. A comissão finaliza quando o processo fecha, e os pagamentos seguem o
--     cronograma (vencimentos até 2028). Nenhum pagamento está em PAGO no CVCRM, então não há data
--     efetiva de pagamento: o que existe é o vencimento programado.
--  2. COMISSÃO DE VALOR ZERO é casca criada na venda, sem regra apurada (1.503 de 3.891, quase todas
--     de 2023 e 2024). `status_comissao` as separa em 'Sem valor apurado', e `eh_comissao_devida`
--     só vale para comissão não cancelada e com valor.
--  3. valor_comissao_apagar e valor_pagamento não entram: o primeiro não cai quando a comissão
--     finaliza e o segundo não é o total. O que vale é valor_comissao e o cronograma de pagamentos.
--
-- `data_finalizacao` e `data_cancelamento` vêm do workflow: a data em que a comissão saiu da etapa
-- anterior, que é quando entrou na atual. Sem passagem registrada, vale a data de criação.
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_comissoes AS
WITH wf AS (
    SELECT id_comissao, max(data_saida) AS data_entrada_situacao
    FROM silver.comissoes_workflow_tempo
    GROUP BY id_comissao
),
pag AS (
    SELECT p.id_comissao,
           count(*)  FILTER (WHERE NOT p.eh_cancelado)             AS qtd_pagamentos,
           sum(p.valor) FILTER (WHERE NOT p.eh_cancelado)          AS valor_pagamentos,
           min(p.vencimento) FILTER (WHERE NOT p.eh_cancelado)     AS primeiro_vencimento,
           max(p.vencimento) FILTER (WHERE NOT p.eh_cancelado)     AS ultimo_vencimento
    FROM silver.comissoes_pagamentos p
    GROUP BY p.id_comissao
)
SELECT
    c.id_comissao,
    c.id_reserva,
    rv.id_empreendimento,
    rv.id_corretor,
    rv.id_imobiliaria,

    c.data_cad::date                                          AS data_cad,
    rv.data_venda::date                                       AS data_venda,
    coalesce(wf.data_entrada_situacao, c.data_cad)::date      AS data_entrada_situacao,
    CASE WHEN c.eh_finalizada THEN coalesce(wf.data_entrada_situacao, c.data_cad)::date END AS data_finalizacao,
    CASE WHEN c.eh_cancelada  THEN coalesce(wf.data_entrada_situacao, c.data_cad)::date END AS data_cancelamento,

    c.empreendimento,
    silver.conformar_empreendimento(c.empreendimento)         AS empreendimento_conformado,
    c.etapa, c.bloco, c.unidade,
    c.imobiliaria,
    coalesce(ih.house_parcerias, 'Parcerias')                 AS house_parcerias,
    c.corretor,
    silver.chave_nome(c.corretor)                             AS corretor_chave,
    c.nota_fiscal,
    (c.nota_fiscal IS NOT NULL)                               AS tem_nota_fiscal,

    c.id_situacao,
    c.situacao,
    c.grupo_situacao,
    c.grupo_situacao_ordem,
    CASE WHEN c.eh_cancelada   THEN 'Cancelada'
         WHEN c.eh_valor_zero  THEN 'Sem valor apurado'
         WHEN c.eh_finalizada  THEN 'Finalizada'
         ELSE 'Em andamento' END                              AS status_comissao,
    c.eh_finalizada,
    c.eh_cancelada,
    c.eh_valor_zero,
    (NOT c.eh_cancelada AND NOT c.eh_valor_zero)              AS eh_comissao_devida,
    (NOT c.eh_cancelada AND NOT c.eh_finalizada AND NOT c.eh_valor_zero) AS eh_em_aberto,
    CASE WHEN NOT c.eh_cancelada AND NOT c.eh_finalizada AND NOT c.eh_valor_zero
         THEN (current_date - coalesce(wf.data_entrada_situacao, c.data_cad)::date) END::int AS dias_na_situacao,

    c.valor_contrato,
    c.porcentagem_comissao,
    c.valor_comissao,
    CASE WHEN c.eh_cancelada THEN 0 ELSE coalesce(c.valor_comissao, 0) END AS valor_devido,
    c.data_pagamento                                          AS data_pagamento_programada,
    coalesce(pag.qtd_pagamentos, 0)::int                      AS qtd_pagamentos,
    pag.valor_pagamentos,
    pag.primeiro_vencimento,
    pag.ultimo_vencimento,

    rv.situacao                                               AS situacao_reserva,
    coalesce(rv.situacao IN ('Distrato', 'Cancelada', 'Vencida'), false) AS eh_reserva_sem_venda,
    -- comissão que segue viva (não cancelada, com valor) numa reserva que não virou venda: o CVCRM
    -- cancela quase todas sozinho quando há distrato (812 de 813), as que sobram precisam de limpeza
    (NOT c.eh_cancelada AND NOT c.eh_valor_zero
        AND coalesce(rv.situacao IN ('Distrato', 'Cancelada', 'Vencida'), false)) AS eh_viva_em_reserva_sem_venda,
    c.ano_cad,
    c.ano_mes_cad
FROM silver.comissoes c
LEFT JOIN wf                              ON wf.id_comissao = c.id_comissao
LEFT JOIN pag                             ON pag.id_comissao = c.id_comissao
LEFT JOIN silver.reservas rv              ON rv.id_reserva = c.id_reserva
LEFT JOIN silver.dpara_imobiliaria_house ih ON ih.imobiliaria = c.imobiliaria;


-- ===========================================================================
-- COMISSÃO: pagamentos programados. Grão = 1 pagamento (id_pagamento). `vencimento` é a data
-- programada (não a data em que se pagou: ver o aviso 1 de gold.fato_comissoes). Serve ao
-- fluxo de desembolso. `eh_obrigacao` é o pagamento que ainda representa um compromisso:
-- não cancelado, de comissão não cancelada e de reserva que virou venda.
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_comissoes_pagamentos AS
SELECT
    p.id_pagamento,
    p.id_comissao,
    c.id_reserva,
    c.id_empreendimento,
    c.imobiliaria,
    c.house_parcerias,
    c.corretor_chave,
    p.vencimento,
    p.ano_mes_vencimento,
    p.valor,
    p.situacao                                                AS situacao_pagamento,
    p.eh_pago,
    p.eh_cancelado,
    c.situacao                                                AS situacao_comissao,
    c.grupo_situacao,
    c.eh_finalizada                                           AS eh_comissao_finalizada,
    c.eh_cancelada                                            AS eh_comissao_cancelada,
    c.situacao_reserva,
    (NOT p.eh_cancelado AND NOT c.eh_cancelada AND NOT c.eh_reserva_sem_venda) AS eh_obrigacao,
    (p.vencimento - current_date)::int                        AS dias_para_vencimento,
    CASE WHEN p.vencimento < current_date                   THEN '1 - Já venceu'
         WHEN p.vencimento <= current_date + 30             THEN '2 - Próximos 30 dias'
         WHEN p.vencimento <= current_date + 90             THEN '3 - 31 a 90 dias'
         WHEN p.vencimento <= current_date + 180            THEN '4 - 91 a 180 dias'
         WHEN p.vencimento <= current_date + 365            THEN '5 - 181 a 365 dias'
         ELSE '6 - Mais de 1 ano' END                         AS faixa_vencimento
FROM silver.comissoes_pagamentos p
JOIN gold.fato_comissoes c ON c.id_comissao = p.id_comissao;


-- ===========================================================================
-- COMISSÃO: cronograma previsto. Grão = 1 parcela prevista de uma regra ativa (id_programacao): o
-- que cada reserva promete pagar de comissão, desde a venda. Cobre reservas que depois cancelaram
-- (63% das parcelas), por isso `eh_reserva_viva` filtra o que ainda vale. Conferido em 06/nov/2026
-- nas reservas vendidas: a soma do cronograma bate com a das regras ativas em 97% e com a dos
-- pagamentos gerados em 97%. É a base da previsão de caixa dos meses à frente, porque cobre também
-- as comissões ainda sem apuração (sem pagamento criado).
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_comissoes_programacao AS
SELECT
    p.id_programacao,
    p.id_reserva,
    p.id_regra,
    rv.id_empreendimento,
    rv.imobiliaria,
    coalesce(ih.house_parcerias, 'Parcerias')                 AS house_parcerias,
    p.parcela,
    p.beneficiario,
    p.beneficiario_grupo,
    p.valor,
    p.data_previsao,
    p.ano_mes_previsao,
    (p.data_previsao - current_date)::int                     AS dias_para_previsao,
    p.eh_dentro_do_contrato,
    rv.situacao                                               AS situacao_reserva,
    (rv.situacao = 'Vendida')                                 AS eh_reserva_viva
FROM silver.comissoes_programacao p
LEFT JOIN silver.reservas rv              ON rv.id_reserva = p.id_reserva
LEFT JOIN silver.dpara_imobiliaria_house ih ON ih.imobiliaria = rv.imobiliaria;


-- ===========================================================================
-- COMISSÃO: regras. Grão = 1 regra (id_regra): quem recebe, de que tipo e quanto. O CVCRM guarda as
-- versões, então o retrato atual é `eh_ativa`. `pct_sobre_contrato` é o valor da regra sobre o
-- contrato da reserva, para as regras em valor fixo ou por série terem uma porcentagem comparável.
-- ===========================================================================
CREATE OR REPLACE VIEW gold.fato_comissoes_regras AS
SELECT
    g.id_regra,
    g.id_reserva,
    rv.id_empreendimento,
    rv.imobiliaria,
    coalesce(ih.house_parcerias, 'Parcerias')                 AS house_parcerias,
    rv.data_venda::date                                       AS data_venda,
    rv.situacao                                               AS situacao_reserva,
    (rv.situacao = 'Vendida')                                 AS eh_reserva_viva,
    g.eh_ativa,
    g.tipo_comissao,
    g.beneficiario,
    g.beneficiario_grupo,
    g.tipo_valor,
    g.valor,
    g.porcentagem,
    rv.valor_contrato                                         AS valor_contrato_reserva,
    CASE WHEN rv.valor_contrato > 0
         THEN round(100 * g.valor / rv.valor_contrato, 4) END AS pct_sobre_contrato,
    g.eh_paga_pela_condicao,
    g.eh_enviada_pagadoria
FROM silver.comissoes_regras g
LEFT JOIN silver.reservas rv              ON rv.id_reserva = g.id_reserva
LEFT JOIN silver.dpara_imobiliaria_house ih ON ih.imobiliaria = rv.imobiliaria;
