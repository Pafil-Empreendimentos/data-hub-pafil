-- Camada SILVER de COMISSÃO e REPASSE (nov/2026): views de conformação sobre a bronze.
-- Aplicar com `python aplicar_silver.py` (entra no fluxo completo) ou, sozinha e sem tocar no
-- resto da silver, com `python aplicar_silver.py --so-comissoes-repasses`.
-- Depende de bronze.comissoes*, bronze.reservas_comissoes*, bronze.repasses*, bronze.workflows_*
-- e das funções de silver.sql (tentar_timestamptz). Análise completa em
-- docs/comissoes-e-repasses.md.
--
-- Escolhas que valem para as duas famílias:
--  * Dado pessoal fica de fora. O nome e o CEP do cliente (comissoes.cliente, repasses.cliente,
--    cep_cliente e o CPF) não entram na silver: nenhuma análise precisa deles, e a ligação com a
--    reserva e com o perfil do cliente se faz por id_reserva e id_cliente.
--  * As definições de workflow (silver.*_situacoes) vêm da própria API do CVCRM, com ordem e
--    flags de início, fim e cancelamento. Quem decide se uma etapa encerra o processo é o
--    CVCRM, não um nome de situação escrito aqui.

CREATE SCHEMA IF NOT EXISTS silver;


-- ===========================================================================
-- CAMPO ADICIONAL MAIS RECENTE. O array campos_adicionais guarda o HISTÓRICO de cada campo
-- customizado (uma entrada por edição, em ordem crescente de idcampo_valores): em 06/nov/2026,
-- 2.236 dos 3.440 repasses tinham o mesmo campo com valores diferentes. Para ler o valor atual
-- vale a entrada de maior idcampo_valores. silver.campo_adicional() (de silver.sql) devolve a
-- PRIMEIRA entrada, ou seja, a mais antiga: ver R28 em docs/regras-de-negocio.md.
-- ===========================================================================
CREATE OR REPLACE FUNCTION silver.campo_adicional_atual(campos jsonb, nome text)
RETURNS text AS $$
    SELECT nullif(btrim(e->>'valor'), '')
    FROM jsonb_array_elements(
        CASE WHEN jsonb_typeof(campos) = 'array' THEN campos ELSE '[]'::jsonb END
    ) e
    WHERE e->>'nome' = nome
    ORDER BY (e->>'idcampo_valores')::bigint DESC NULLS LAST
    LIMIT 1;
$$ LANGUAGE sql IMMUTABLE;


-- ===========================================================================
-- REPASSE: DEFINIÇÃO DAS ETAPAS (workflow). Grão = 1 situação do workflow de repasses.
-- `ordem` e as flags vêm do CVCRM (bronze.workflows_repasses). `fase` é o agrupamento de
-- negócio das 35 etapas em 8 fases, escrito aqui porque a API não o fornece (o campo `grupos`
-- do workflow vem vazio). É uma PROPOSTA de agrupamento a revisar com o time de repasse:
-- mudar o rótulo de uma fase é só editar a lista abaixo. Etapa nova que o CVCRM criar e que
-- não estiver na lista cai em "9. Outras etapas" e fica visível no gráfico.
--   1 a 4  o caminho feliz, na ordem do workflow
--   5      finalizado (flag fim)
--   6      pendências e exceções (a equipe precisa agir)
--   7      Aguardando APF e Finan. Chaves: esperas longas por desenho (o repasse só anda
--          quando um marco externo acontece), por isso não contam como "parado"
--   8      encerrados sem repasse (cancelado, distrato, cessão de direitos)
-- ===========================================================================
CREATE OR REPLACE VIEW silver.repasses_situacoes AS
WITH atuais AS (
    SELECT
        w.idsituacao::bigint                                   AS id_situacao,
        btrim(w.nome)                                          AS situacao,
        w.ordem::int                                           AS ordem,
        (upper(coalesce(w.flags->>'inicio',    '')) = 'S')     AS eh_inicio,
        (upper(coalesce(w.flags->>'fim',       '')) = 'S')     AS eh_fim,
        (upper(coalesce(w.flags->>'cancelado', '')) = 'S')     AS eh_cancelado,
        (upper(coalesce(w.flags->>'distrato',  '')) = 'S')     AS eh_distrato,
        (upper(coalesce(w.flags->>'cessao',    '')) = 'S')     AS eh_cessao,
        false                                                  AS eh_descontinuada,
        w.cor_bg                                               AS cor_fundo
    FROM bronze.workflows_repasses w
),
-- Etapas que existiram e foram removidas do workflow (o histórico ainda cita 15 delas, como
-- "Pré Análise" e "Dossiê Conformidade", em 2% das passagens). Sem elas o tempo por etapa
-- perderia essas passagens. Não têm ordem nem flag: nenhum repasse está nelas hoje.
descontinuadas AS (
    SELECT DISTINCT ON (x.id)
        x.id::bigint                                           AS id_situacao,
        btrim(x.nome)                                          AS situacao,
        NULL::int                                              AS ordem,
        false AS eh_inicio, false AS eh_fim, false AS eh_cancelado,
        false AS eh_distrato, false AS eh_cessao,
        true                                                   AS eh_descontinuada,
        NULL::text                                             AS cor_fundo
    FROM (
        SELECT h.para AS id, h.para_nome AS nome FROM bronze.repasses_historico_situacoes h
        UNION ALL
        SELECT h.de,   h.de_nome   FROM bronze.repasses_historico_situacoes h
    ) x
    WHERE x.id IS NOT NULL AND x.id > 0
      AND NOT EXISTS (SELECT 1 FROM bronze.workflows_repasses w WHERE w.idsituacao = x.id)
    ORDER BY x.id, x.nome
),
todas AS (
    SELECT * FROM atuais
    UNION ALL
    SELECT * FROM descontinuadas
)
SELECT
    t.id_situacao,
    t.situacao,
    t.ordem,
    t.eh_inicio, t.eh_fim, t.eh_cancelado, t.eh_distrato, t.eh_cessao,
    t.eh_descontinuada,
    coalesce(f.fase, '9. Outras etapas')                       AS fase,
    coalesce(f.fase_ordem, 9)::smallint                        AS fase_ordem,
    t.cor_fundo
FROM todas t
LEFT JOIN (VALUES
    (1,  '1. Documentação e conformidade',   1),   -- Em espera
    (23, '1. Documentação e conformidade',   1),   -- DOSSIÊ | FGTS | Emissão de Formulários
    (50, '1. Documentação e conformidade',   1),   -- Assinatura de formulários
    (45, '1. Documentação e conformidade',   1),   -- Conformidade - CEHOP
    (26, '1. Documentação e conformidade',   1),   -- Conforme | Validação Pafil
    (24, '2. Entrevista, minuta e assinatura', 2), -- Agendar Entrevista
    (28, '2. Entrevista, minuta e assinatura', 2), -- Entrevista
    (46, '2. Entrevista, minuta e assinatura', 2), -- Emissão de Minuta e Conferência
    (59, '2. Entrevista, minuta e assinatura', 2), -- Confissão de Dívida
    (38, '2. Entrevista, minuta e assinatura', 2), -- Aguardando Assinatura
    (34, '2. Entrevista, minuta e assinatura', 2), -- Assinatura Concluida
    (36, '3. ITBI e cartório',                3),  -- Recolhimento | ITBI
    (55, '3. ITBI e cartório',                3),  -- Tx. Prenotação | Cartório
    (68, '3. ITBI e cartório',                3),  -- Protocolado PM - ITBI
    (39, '3. ITBI e cartório',                3),  -- Prenotado | Cartório
    (57, '3. ITBI e cartório',                3),  -- Registro pendente | Custas ONR
    (58, '3. ITBI e cartório',                3),  -- Aguardando Registro | Cartório
    (42, '4. Liberação de recursos',          4),  -- Aguardando Liberação dos Recursos
    (5,  '5. Repasse finalizado',             5),  -- Repasse Finalizado
    (49, '6. Pendências e exceções',          6),  -- Pendência
    (60, '6. Pendências e exceções',          6),  -- Pendência Comercial
    (20, '6. Pendências e exceções',          6),  -- Retenção
    (52, '6. Pendências e exceções',          6),  -- 1° Notificação
    (53, '6. Pendências e exceções',          6),  -- 2° Notificação
    (51, '6. Pendências e exceções',          6),  -- Juridico
    (56, '6. Pendências e exceções',          6),  -- Exigência | Cartório
    (21, '6. Pendências e exceções',          6),  -- Divergência | Renegociação Cliente
    (63, '6. Pendências e exceções',          6),  -- Avalista | tratativas repasse
    (4,  '6. Pendências e exceções',          6),  -- Atualização Documental
    (8,  '6. Pendências e exceções',          6),  -- Conferência | Reavaliar
    (47, '7. Aguardando (APF e chaves)',      7),  -- Aguardando APF
    (48, '7. Aguardando (APF e chaves)',      7),  -- Finan. Chaves
    (10, '8. Encerrado sem repasse',          8),  -- Cancelado
    (15, '8. Encerrado sem repasse',          8),  -- Distrato
    (64, '8. Encerrado sem repasse',          8),  -- Cessão de direitos
    -- etapas descontinuadas, só as que têm um lugar óbvio no fluxo atual:
    (19, '1. Documentação e conformidade',   1),   -- Pré Análise
    (25, '1. Documentação e conformidade',   1),   -- Dossiê Conformidade
    (29, '2. Entrevista, minuta e assinatura', 2), -- Conferindo Minuta
    (30, '2. Entrevista, minuta e assinatura', 2), -- Termo de Crédito
    (31, '2. Entrevista, minuta e assinatura', 2), -- Confissão de Dívida (antiga)
    (33, '2. Entrevista, minuta e assinatura', 2), -- Assinatura Eletrônica
    (35, '2. Entrevista, minuta e assinatura', 2), -- Assinatura Concluída (antiga)
    (43, '3. ITBI e cartório',                3),  -- Devolução Vias
    (27, '6. Pendências e exceções',          6),  -- Inconforme
    (54, '6. Pendências e exceções',          6),  -- Comercial | RETENÇÃO
    (66, '6. Pendências e exceções',          6),  -- Reversão | tratativas crédito
    (16, '8. Encerrado sem repasse',          8)   -- Cessão (antiga)
) AS f(id_situacao, fase, fase_ordem) ON f.id_situacao = t.id_situacao;


-- ===========================================================================
-- REPASSE: 1 linha por repasse (idrepasse). É 1:1 com a reserva (id_reserva). Só a data da
-- última modificação foi renomeada para o que ela é (a API manda `data_modificao`, sem o "c").
-- Dinheiro: valor_financiado = valor_divida + valor_subsidio + valor_fgts, que é o que o banco
-- coloca no repasse. Só é confiável a partir de 2025: os repasses de 2023 e 2024 vieram da
-- migração para o CVCRM, e 629 dos finalizados deles têm tudo zerado (`tem_valor_financiado`).
-- valor_contrato vem preenchido em todos e é igual ao da reserva.
-- Campos adicionais: ver silver.campo_adicional_atual acima. modalidade_financiamento e
-- tipo_venda_repasse são preenchidos em cerca de 97% dos repasses.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.repasses AS
SELECT
    r.idrepasse::bigint                                    AS id_repasse,
    r.idreserva::bigint                                    AS id_reserva,
    r.idempreendimento::bigint                             AS id_empreendimento,
    r.codigointerno_empreendimento::bigint                 AS codigo_interno_empreendimento,
    r.idunidade::bigint                                    AS id_unidade,
    r.idcliente::bigint                                    AS id_cliente,
    nullif(btrim(r.idlead), '')                            AS ids_lead,   -- pode vir "166902,164524"

    btrim(r.empreendimento)                                AS empreendimento,
    btrim(r.etapa)                                         AS etapa,
    btrim(r.bloco)                                         AS bloco,
    btrim(r.unidade)                                       AS unidade,
    btrim(r.regiao)                                        AS regiao,

    r.idsituacao::bigint                                   AS id_situacao,
    btrim(r.situacao)                                      AS situacao,
    s.ordem                                                AS ordem_etapa,
    coalesce(s.fase, '9. Outras etapas')                   AS fase,
    coalesce(s.fase_ordem, 9)::smallint                    AS fase_ordem,
    coalesce(s.eh_inicio,    false)                        AS eh_inicio,
    coalesce(s.eh_fim,       false)                        AS eh_finalizado,
    coalesce(s.eh_cancelado, false)                        AS eh_cancelado,
    coalesce(s.eh_distrato,  false)                        AS eh_distrato,
    coalesce(s.eh_cessao,    false)                        AS eh_cessao,
    -- Encerrado = chegou a um fim, seja ele o repasse feito ou não. Em andamento é o resto.
    (coalesce(s.eh_fim, false) OR coalesce(s.eh_cancelado, false)
        OR coalesce(s.eh_distrato, false) OR coalesce(s.eh_cessao, false)) AS eh_encerrado,

    nullif(btrim(r.correspondente), '')                    AS correspondente,
    nullif(btrim(r.banco), '')                             AS banco,
    nullif(btrim(r.agencia), '')                           AS agencia,
    btrim(r.contrato)                                      AS situacao_contrato,   -- Adimplente | Inadimplente
    (upper(coalesce(r.itbi_pago, ''))       = 'S')         AS eh_itbi_pago,
    (upper(coalesce(r.registro_pago, ''))   = 'S')         AS eh_registro_pago,

    r.valor_contrato,
    r.valor_financiado,
    r.valor_divida,
    r.valor_subsidio,
    r.valor_fgts,
    r.valor_previsto,
    r.parcela_conclusao,
    r.saldo_devedor,
    r.valor_registro,
    (coalesce(r.valor_financiado, 0) > 0)                  AS tem_valor_financiado,

    r.data_cad,
    r.data_venda,
    r.data_alteracao_status,
    r.data_modificao                                       AS data_modificacao,
    r.data_registro,
    r.proxima_acao,
    r.data_recurso_liberado,
    EXTRACT(YEAR  FROM r.data_cad)::int                    AS ano_cad,
    to_char(r.data_cad, 'YYYY-MM')                         AS ano_mes_cad,

    silver.campo_adicional_atual(r.campos_adicionais, 'Modalidade Financiamento') AS modalidade_financiamento,
    silver.campo_adicional_atual(r.campos_adicionais, 'Tipo de Venda')             AS tipo_venda_repasse,
    CASE upper(silver.campo_adicional_atual(r.campos_adicionais, 'Utilização de FGTS'))
         WHEN 'SIM' THEN 'Sim'
         WHEN 'NÃO' THEN 'Não'
    END                                                    AS utiliza_fgts,
    silver.campo_adicional_atual(r.campos_adicionais, 'Aprovação de crédito')      AS aprovacao_credito,

    r._data_extracao
FROM bronze.repasses r
LEFT JOIN silver.repasses_situacoes s ON s.id_situacao = r.idsituacao::bigint;


-- ===========================================================================
-- REPASSE: histórico de situações. Grão = 1 mudança de situação (id_historico). `id_de` e
-- `id_para` são ids do workflow (silver.repasses_situacoes). A data em que o repasse foi
-- finalizado é a data da transição cujo destino é a situação de fim. `eh_correspondente` marca
-- a mudança feita por quem trabalha no correspondente bancário (40% das mudanças): nela o
-- campo usuario vem vazio e correspondente traz a empresa.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.repasses_historico AS
SELECT
    h.idhistorico::bigint                                  AS id_historico,
    h.idrepasse::bigint                                    AS id_repasse,
    h.data_cad                                             AS data_movimento,
    h.de::bigint                                           AS id_de,
    btrim(h.de_nome)                                       AS situacao_de,
    h.para::bigint                                         AS id_para,
    btrim(h.para_nome)                                     AS situacao_para,
    nullif(h.idusuario, 0)::bigint                         AS id_usuario,
    nullif(btrim(h.usuario), '')                           AS usuario,
    (coalesce(h.idcorrespondente, 0) > 0)                  AS eh_correspondente,
    nullif(btrim(h.correspondente), '')                    AS correspondente,
    h._data_extracao
FROM bronze.repasses_historico_situacoes h;


-- ===========================================================================
-- REPASSE: tempo por etapa. Grão = 1 passagem do repasse por uma etapa (id_tempo). `tempo_min`
-- é quanto ficou nela, em MINUTOS (conferido em 06/nov/2026: bate com a diferença entre
-- entrada e saída no histórico em 27.622 de 27.701 passagens), e `data_saida` é o momento em
-- que SAIU dela. A etapa em que o repasse está agora ainda não tem linha.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.repasses_workflow_tempo AS
SELECT
    w.idtempo::bigint                                      AS id_tempo,
    w.idrepasse::bigint                                    AS id_repasse,
    w.idsituacao::bigint                                   AS id_situacao,
    btrim(w.situacao)                                      AS situacao,
    w.tempo                                                AS tempo_min,
    w.data_cad                                             AS data_saida,
    w._data_extracao
FROM bronze.repasses_workflow_tempo w;


-- ===========================================================================
-- COMISSÃO: DEFINIÇÃO DAS SITUAÇÕES (workflow). Duas listas: a da COMISSÃO (7 situações) e a do
-- PAGAMENTO dela (11). O CVCRM chama o cancelamento de `cancelada` num e `cancelado` no outro.
-- `grupo` agrupa a comissão em 6 estágios para o funil. As variantes de desligamento (8 e 9)
-- são comissões de corretor que saiu da empresa, que esperam a nota fiscal por outro caminho.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.comissoes_situacoes AS
SELECT
    w.idsituacao::bigint                                       AS id_situacao,
    btrim(w.nome)                                              AS situacao,
    w.ordem::int                                               AS ordem,
    (upper(coalesce(w.flags->>'inicio',    '')) = 'S')         AS eh_inicio,
    (upper(coalesce(w.flags->>'fim',       '')) = 'S')         AS eh_fim,
    (upper(coalesce(w.flags->>'cancelada', '')) = 'S')         AS eh_cancelada,
    coalesce(g.grupo, '9. Outras situações')                   AS grupo,
    coalesce(g.grupo_ordem, 9)::smallint                       AS grupo_ordem
FROM bronze.workflows_comissoes w
LEFT JOIN (VALUES
    (1, '1. Em apuração',                 1),   -- Aguardando Apuração
    (2, '2. Aguardando NF',               2),   -- Aguardando NF
    (8, '3. Desligamento, NF pendente',   3),   -- Aguardando NF - Desligamento
    (9, '3. Desligamento, NF pendente',   3),   -- Aguardando Desligamento - Solicitado 50%
    (4, '4. NF lançada',                  4),   -- NF Lançada
    (5, '5. Finalizada',                  5),   -- Finalizado
    (3, '6. Cancelada',                   6)    -- Cancelada
) AS g(id_situacao, grupo, grupo_ordem) ON g.id_situacao = w.idsituacao::bigint;


CREATE OR REPLACE VIEW silver.comissoes_pagamentos_situacoes AS
SELECT
    w.idsituacao::bigint                                       AS id_situacao,
    btrim(w.nome)                                              AS situacao,
    w.ordem::int                                               AS ordem,
    (upper(coalesce(w.flags->>'inicio',    '')) = 'S')         AS eh_inicio,
    (upper(coalesce(w.flags->>'fim',       '')) = 'S')         AS eh_pago,
    (upper(coalesce(w.flags->>'cancelado', '')) = 'S')         AS eh_cancelado
FROM bronze.workflows_comissoes_pagamentos w;


-- ===========================================================================
-- COMISSÃO: 1 linha por comissão (id_comissao). Uma reserva pode ter mais de uma: quando as
-- regras mudam, o CVCRM cancela a comissão antiga e gera outra (a reserva 3371 tem três, duas
-- canceladas). Por isso somar valor_comissao pede excluir as canceladas.
-- Pontos de atenção, conferidos na produção em 06/nov/2026 (ver docs/comissoes-e-repasses.md):
--  * "Finalizado" NÃO é "pago". A comissão finaliza quando o processo dela fecha e os
--    pagamentos seguem o cronograma (a data de vencimento chega a 2028). Nenhum pagamento está
--    na situação PAGO, então a data efetiva de pagamento não é observável.
--  * valor_comissao_apagar não cai quando a comissão finaliza (é igual ao valor total em
--    1.165 das 1.205 finalizadas): não serve como saldo a pagar.
--  * 1.503 das 3.891 comissões têm valor zero (1.264 delas "Aguardando Apuração", quase todas
--    de 2023 e 2024): são cascas criadas na venda, sem regra calculada. `eh_valor_zero`.
--  * data_pagamento é a data programada do pagamento, e não a data em que foi pago.
-- Cliente e CEP ficam de fora (dado pessoal).
-- ===========================================================================
CREATE OR REPLACE VIEW silver.comissoes AS
SELECT
    c.idcomissao::bigint                                   AS id_comissao,
    c.idreserva::bigint                                    AS id_reserva,
    c.idsituacao::bigint                                   AS id_situacao,
    btrim(c.situacao)                                      AS situacao,
    coalesce(s.grupo, '9. Outras situações')               AS grupo_situacao,
    coalesce(s.grupo_ordem, 9)::smallint                   AS grupo_situacao_ordem,
    coalesce(s.eh_inicio,   false)                         AS eh_inicio,
    coalesce(s.eh_fim,      false)                         AS eh_finalizada,
    coalesce(s.eh_cancelada, false)                        AS eh_cancelada,

    btrim(c.corretor)                                      AS corretor,
    btrim(c.imobiliaria)                                   AS imobiliaria,
    btrim(c.empreendimento)                                AS empreendimento,
    btrim(c.etapa)                                         AS etapa,
    btrim(c.bloco)                                         AS bloco,
    btrim(c.unidade)                                       AS unidade,
    btrim(c.regiao)                                        AS regiao,

    c.valor_contrato,
    c.porcentagem_comissao,
    c.valor_comissao,
    c.valor_comissao_apagar,
    c.valor_pagamento,
    (coalesce(c.valor_comissao, 0) = 0)                    AS eh_valor_zero,
    nullif(btrim(c.nota_fiscal), '')                       AS nota_fiscal,
    silver.tentar_timestamptz(c.data_pagamento)::date      AS data_pagamento,

    c.data_cad,
    EXTRACT(YEAR  FROM c.data_cad)::int                    AS ano_cad,
    to_char(c.data_cad, 'YYYY-MM')                         AS ano_mes_cad,
    c._data_extracao
FROM bronze.comissoes c
LEFT JOIN silver.comissoes_situacoes s ON s.id_situacao = c.idsituacao::bigint;


-- ===========================================================================
-- COMISSÃO: pagamentos (parcelas). Grão = 1 pagamento (id_pagamento). `vencimento` é a data
-- programada. O workflow do pagamento tem PAGO, mas nenhum pagamento chegou lá: "NF Lançada" é
-- a situação mais avançada que existe nos dados. Só 1.662 das 3.891 comissões têm pagamento
-- (as demais são cascas de valor zero). Linhas apagadas na origem saem da bronze pelo
-- espelho (R27), então a soma aqui bate com o CVCRM.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.comissoes_pagamentos AS
SELECT
    p.idpagamento::bigint                                  AS id_pagamento,
    p.idcomissao::bigint                                   AS id_comissao,
    btrim(p.situacao)                                      AS situacao,
    coalesce(s.eh_pago, false)                             AS eh_pago,
    coalesce(s.eh_cancelado, false)                        AS eh_cancelado,
    p.valor,
    p.vencimento,
    to_char(p.vencimento, 'YYYY-MM')                       AS ano_mes_vencimento,
    btrim(p.bloco)                                         AS bloco,
    btrim(p.unidade)                                       AS unidade,   -- texto livre: "153 - TERRENISTA", "Lote 5 Casa 05"
    nullif(btrim(p.idboleto), '')                          AS id_boleto,
    p._data_extracao
FROM bronze.comissoes_pagamentos p
LEFT JOIN silver.comissoes_pagamentos_situacoes s ON s.situacao = btrim(p.situacao);


-- ===========================================================================
-- COMISSÃO: tempo por situação do workflow. Mesma forma de silver.repasses_workflow_tempo
-- (tempo em MINUTOS, data_saida é quando saiu da situação, a atual não tem linha).
-- ===========================================================================
CREATE OR REPLACE VIEW silver.comissoes_workflow_tempo AS
SELECT
    w.idtempo::bigint                                      AS id_tempo,
    w.idcomissao::bigint                                   AS id_comissao,
    w.idsituacao::bigint                                   AS id_situacao,
    btrim(w.situacao)                                      AS situacao,
    w.tempo                                                AS tempo_min,
    w.data_cad                                             AS data_saida,
    w._data_extracao
FROM bronze.comissoes_workflow_tempo w;


-- ===========================================================================
-- COMISSÃO: regras da reserva. Grão = 1 regra (id_regra): quem recebe, quanto e de que tipo.
-- O CVCRM guarda as VERSÕES das regras: cada edição cria linhas novas e marca as antigas como
-- inativas. Em 06/nov/2026 eram 6.886 ativas de 10.489. Para o retrato atual, filtre eh_ativa;
-- a soma das regras ativas bate com porcentagem_comissao da comissão gerada (reserva 3371:
-- 4% + 0,6% + 0,1% + 0,1% + 0,2% = 5,000001%).
-- Códigos decodificados da referência da API:
--   para: IC imobiliária, IR imobiliária da reserva, CO imobiliária coordenação, CC corretor,
--         CR corretor da reserva, CP coordenador do produto, UI usuário da imobiliária,
--         UA usuário administrativo (equipe interna da Pafil).
--   comissao_tipo: C comissão, P prêmio, E prêmio extra.
--   tipo_valor: P percentual, V valor fixo, VSC valor da série, PRT premiação pela regra da
--               tabela de preço.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.comissoes_regras AS
SELECT
    rc.id::bigint                                          AS id_regra,
    rc.idreserva::bigint                                   AS id_reserva,
    rc.idimobiliaria::bigint                               AS id_imobiliaria,
    rc.idcorretor::bigint                                  AS id_corretor,
    rc.quem::bigint                                        AS id_beneficiario,
    rc.ordem::int                                          AS ordem,
    (upper(coalesce(rc.ativo, '')) = 'S')                  AS eh_ativa,
    rc.data_cad,

    rc.comissao_tipo                                       AS cod_tipo_comissao,
    CASE rc.comissao_tipo
         WHEN 'C' THEN 'Comissão'
         WHEN 'P' THEN 'Prêmio'
         WHEN 'E' THEN 'Prêmio extra'
         ELSE coalesce(rc.comissao_tipo, 'Não informado')
    END                                                    AS tipo_comissao,
    rc.para                                                AS cod_beneficiario,
    CASE rc.para
         WHEN 'IC' THEN 'Imobiliária'
         WHEN 'IR' THEN 'Imobiliária da reserva'
         WHEN 'CO' THEN 'Imobiliária coordenação'
         WHEN 'CC' THEN 'Corretor'
         WHEN 'CR' THEN 'Corretor da reserva'
         WHEN 'CP' THEN 'Coordenador do produto'
         WHEN 'UI' THEN 'Usuário da imobiliária'
         WHEN 'UA' THEN 'Usuário administrativo'
         ELSE coalesce(rc.para, 'Não informado')
    END                                                    AS beneficiario,
    CASE
         WHEN rc.para IN ('IC', 'IR', 'CO') THEN 'Imobiliária'
         WHEN rc.para IN ('CC', 'CR')       THEN 'Corretor'
         WHEN rc.para IN ('UA', 'CP')       THEN 'Equipe interna'
         WHEN rc.para = 'UI'                THEN 'Usuário da imobiliária'
         ELSE 'Não informado'
    END                                                    AS beneficiario_grupo,
    rc.tipo_valor                                          AS cod_tipo_valor,
    CASE rc.tipo_valor
         WHEN 'P'   THEN 'Percentual'
         WHEN 'V'   THEN 'Valor fixo'
         WHEN 'VSC' THEN 'Valor da série'
         WHEN 'PRT' THEN 'Premiação da tabela'
         ELSE coalesce(rc.tipo_valor, 'Não informado')
    END                                                    AS tipo_valor,
    rc.valor,
    rc.porcentagem,
    nullif(btrim(rc.descricao), '')                        AS descricao,
    nullif(btrim(rc.forma_pagamento), '')                  AS forma_pagamento,
    (upper(coalesce(rc.pago_pela_condicao_reserva, '')) = 'S') AS eh_paga_pela_condicao,
    (upper(coalesce(rc.enviar_pagadoria, ''))           = 'S') AS eh_enviada_pagadoria,
    (upper(coalesce(rc.editado, ''))                    = 'S') AS eh_editada,
    rc._data_extracao
FROM bronze.reservas_comissoes rc;


-- ===========================================================================
-- COMISSÃO: cronograma previsto. Grão = 1 parcela prevista de uma regra (id_programacao).
-- É o que a reserva promete pagar, desde a venda, mesmo antes de a comissão existir como
-- registro (as cascas de valor zero não têm pagamento, mas têm cronograma). Cobre também
-- reservas que depois cancelaram: para prever caixa, cruze com a situação da reserva (gold).
-- `id_beneficiario` é o id de quem recebe, na natureza indicada por `beneficiario`.
-- ===========================================================================
CREATE OR REPLACE VIEW silver.comissoes_programacao AS
SELECT
    p.idprogramacao::bigint                                AS id_programacao,
    p.idreserva::bigint                                    AS id_reserva,
    p.idregra::bigint                                      AS id_regra,
    p.idreservascondicoes::bigint                          AS id_condicao,
    p.idcondicoes_parcelas::bigint                         AS id_parcela_condicao,
    p.parcela::int                                         AS parcela,
    p.quem::bigint                                         AS id_beneficiario,
    p.para                                                 AS cod_beneficiario,
    CASE p.para
         WHEN 'IC' THEN 'Imobiliária'
         WHEN 'IR' THEN 'Imobiliária da reserva'
         WHEN 'CO' THEN 'Imobiliária coordenação'
         WHEN 'CC' THEN 'Corretor'
         WHEN 'CR' THEN 'Corretor da reserva'
         WHEN 'CP' THEN 'Coordenador do produto'
         WHEN 'UI' THEN 'Usuário da imobiliária'
         WHEN 'UA' THEN 'Usuário administrativo'
         ELSE coalesce(p.para, 'Não informado')
    END                                                    AS beneficiario,
    CASE
         WHEN p.para IN ('IC', 'IR', 'CO') THEN 'Imobiliária'
         WHEN p.para IN ('CC', 'CR')       THEN 'Corretor'
         WHEN p.para IN ('UA', 'CP')       THEN 'Equipe interna'
         WHEN p.para = 'UI'                THEN 'Usuário da imobiliária'
         ELSE 'Não informado'
    END                                                    AS beneficiario_grupo,
    p.valor,
    p.data_previsao,
    to_char(p.data_previsao, 'YYYY-MM')                    AS ano_mes_previsao,
    p.data_previsao_pagadoria,
    (upper(coalesce(p.contrato, '')) = 'S')                AS eh_dentro_do_contrato,
    nullif(btrim(p.forma_pagamento), '')                   AS forma_pagamento,
    p.data_cad,
    p._data_extracao
FROM bronze.reservas_comissoes_programacao p;
