# Inventário da API CVDW do CVCRM

Gerado em 06/11/2026 12:20 por `python -m ferramentas.inventariar_cvdw`.
Fonte: índice do portal do desenvolvedor (https://desenvolvedor.cvcrm.com.br/llms.txt) e a página de cada referência.
Todas as chamadas são GET e a contagem é a que a própria API reporta no envelope
(`total_de_registros`). Para atualizar este arquivo, rode a ferramenta de novo.

## Resumo

- Endpoints no catálogo CVDW: **79**.
- Já ingeridos na bronze (`config/objetos.yml`): **27**.
- Com registros: **71**. Vazios: **6**. Com erro ou sem permissão: **2**.

A coluna Ingestão mostra o nome lógico do objeto na bronze, ou `não`.

## Comissão e Repasse (foco desta análise)

### Endpoints dos dois módulos

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `comissoes` | Retorna as comissões | 3.891 | 24 | `comissoes` |
| `comissoes/pagamentos` | Retorna os pagamentos das comissões | 4.410 | 10 | `comissoes_pagamentos` |
| `comissoes/workflow/tempo` | Retorna o tempo da comissão em cada situação do workflow | 8.411 | 10 | `comissoes_workflow_tempo` |
| `reservas/comissoes` | Retorna os dados de comissão na reserva | 10.489 | 35 | `reservas_comissoes` |
| `reservas/comissoes/programacao` | Retorna os dados da programação da comissão na reserva | 18.129 | 21 | `reservas_comissoes_programacao` |
| `repasses` | Retorna os dados dos repasses | 3.440 | 63 | `repasses` |
| `repasses/workflow/tempo` | Retorna o tempo que o repasse ficou em uma determinada situação. | 31.112 | 10 | `repasses_workflow_tempo` |
| `repasses/historico/situacoes` | Retorna o histórico das situações do repasse | 31.782 | 14 | `repasses_historico_situacoes` |
| `correspondentes-usuarios` | Retorna os usuários correspondentes | 30 | 15 | não |
| `correspondentes-empresas` | Retorna as empresas correspondentes | 7 | 12 | não |

### Campos que cada um devolve

**`comissoes`** (24 campos)

```
referencia, referencia_data, ativo, idcomissao, situacao, idsituacao, idreserva, corretor, imobiliaria, empreendimento, etapa, bloco, unidade, regiao, cliente, cep_cliente, valor_contrato, porcentagem_comissao, valor_comissao, valor_comissao_apagar, valor_pagamento, nota_fiscal, data_pagamento, data_cad
```

**`comissoes/pagamentos`** (10 campos)

```
referencia, referencia_data, idcomissao, idpagamento, valor, vencimento, bloco, unidade, situacao, idBoleto
```

**`comissoes/workflow/tempo`** (10 campos)

```
referencia, referencia_data, ativo, idcomissao, idsituacao, situacao, sigla, idtempo, tempo, data_cad
```

**`reservas/comissoes`** (35 campos)

```
referencia, referencia_data, ativo, id, data_cad, diferenca, tipo, valor, porcentagem, descricao, idreserva, idimobiliaria, idcorretor, comissao_tipo, comissao_pagamento_tipo, codigointerno, tipo_valor, forma_pagamento, pago_pela_condicao_reserva, contrato, para, quem, ordem, enviar_pagadoria, editado, para_pagamento, idusuario_nivel, idusuario_categoria, idcorretor_nivel, idcorretor_categoria, fifty, fifty_idreferencia, id_sub_regra_comissao, idreserva_comissao_lancamento, valor_porcentagem_premiacao
```

**`reservas/comissoes/programacao`** (21 campos)

```
referencia, referencia_data, ativo, idprogramacao, idreserva, idreservascondicoes, idcondicoes_parcelas, idregra, contrato, parcela, para, quem, valor, data_previsao, data_previsao_pagadoria, forma_pagamento, idgestaocontrato_lancamento, idreserva_comissao_parcela_lancamento, idlancamento, idprogramacao_lancamento, data_cad
```

**`repasses`** (63 campos)

```
referencia, referencia_data, ativo, idrepasse, idsituacao, data_cad, ultima_atualizacao, data_modificao_situacao, data_modificao, situacao, idreserva, idempreendimento, codigointerno_empreendimento, empreendimento, etapa, bloco, unidade, regiao, idcliente, documento_cliente, cliente, cep_cliente, parcela, idcontrato, contrato, contrato_quitado, contrato_liquidado, valor_previsto, parcela_conclusao, saldo_devedor, valor_divida, valor_subsidio, valor_fgts, valor_registro, valor_financiado, data_status_financiamento, registro_pago, valor_contrato, numero_contrato, data_registro, correspondente, banco, agencia, data_alteracao_status, data_venda, data_contrato_contabilizado, data_contrato_liberado, data_assinatura_de_contrato, liberar_assinatura, proxima_acao, num_matricula, recebendo_financiamento, itbi_pago, laudemio_pago, idlead, data_unidade_liberada, data_laudo_liberado, data_recurso_liberado, data_sincronizacao, data_cadastro, idunidade, reserva, campos_adicionais
```

**`repasses/workflow/tempo`** (10 campos)

```
referencia, referencia_data, ativo, idtempo, idrepasse, idsituacao, situacao, sigla, tempo, data_cad
```

**`repasses/historico/situacoes`** (14 campos)

```
referencia, referencia_data, ativo, idhistorico, idrepasse, idusuario, usuario, idcorrespondente, correspondente, data_cad, de, para, de_nome, para_nome
```

**`correspondentes-usuarios`** (15 campos)

```
idusuario, referencia, idempresa, nome, documento, departamento, funcao, telefone, celular, email, gerente, ativo_login, data_nasc, data_cad, referencia_data
```

**`correspondentes-empresas`** (12 campos)

```
referencia, referencia_data, idempresa, nome, regiao, telefone, estado, cidade, endereco, email, dias_agendamento, data_cad
```

## Catálogo completo, por grupo

### Comissões

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `comissoes` | Retorna as comissões | 3.891 | 24 | `comissoes` |
| `comissoes/pagamentos` | Retorna os pagamentos das comissões | 4.410 | 10 | `comissoes_pagamentos` |
| `comissoes/workflow/tempo` | Retorna o tempo da comissão em cada situação do workflow | 8.411 | 10 | `comissoes_workflow_tempo` |

### Distratos

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `distratos` | Retorna os distratos | 794 | 30 | `distratos` |

### Reservas

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `reservas` | Retorna as reservas | 4.904 | 96 | `reservas` |
| `reservas/comissoes` | Retorna os dados de comissão na reserva | 10.489 | 35 | `reservas_comissoes` |
| `reservas/comissoes/programacao` | Retorna os dados da programação da comissão na reserva | 18.129 | 21 | `reservas_comissoes_programacao` |
| `reservas/coordenador` | Retorna os dados dos coordenadores da reserva | 0 | - | não |
| `reservas/historico/situacoes` | Retorna os dados históricos das situações das reservas | 26.539 | 12 | `reservas_historico_situacoes` |
| `reservas/historico` | Retorna os dados do histórico da reserva | 386.681 | 12 | não |
| `reservas/condicoes` | Retorna os dados das condições da reserva | 30.563 | 17 | `reservas_condicoes` |
| `reservas/associados` | Retorna os dados dos associados da reserva | 885 | 12 | não |
| `reservas/contratos` | Retorna os dados dos contratos da reserva | 12.134 | 46 | `reservas_contratos` |
| `reservas/workflow/tempo` | Retorna os dados do workflow de reservas | 26.789 | 10 | não |
| `reservas/campos-adicionais` | Retorna os dados dos campos adicionais de reservas | 3.784 | 11 | não |
| `reservas/sienge` | Retorna os dados das reservas do Sienge | erro | - | não |
| `reservas/registros/flags` | Retorna as situações em que a reserva passou | 4.904 | 75 | não |

### Simulações

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `simulacoes` | Retorna os dados das simulações | 6 | 84 | não |

### Vendas

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `vendas` | Retorna os dados das vendas | 2.727 | 47 | `vendas` |

### Unidades

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `unidades/situacao` | Retorna situacao das unidades | 13.386 | 20 | não |
| `unidades/precos` | Valores das unidades das tabelas dinâmicas (Valor unidades) | 3.167 | 18 | não |
| `unidades` | Retorna os dados das unidades | 5.910 | 56 | `unidades` |

### Agendamentos

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `agendamentos/vistorias` | Retorna os dados das vistorias | 1 | 27 | não |
| `v2/cvdw/agendamentos/vistorias` | Retorna agendamentos vistorias | erro | - | não |

### Assistências

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `assistencias` | Retorna os dados das assistências | 2 | 42 | não |
| `assistencias/workflow/tempo` | Retorna o tempo que a assistência passou em cada situação. | 6 | 10 | não |
| `assistencias/itens` | Retorna os dados dos itens das assistências | 2 | 19 | não |
| `assistencias/itens/workflow/tempo` | Retorna o tempo que o item da assistência passou em cada situação. | 0 | - | não |
| `assistencias/visitas/workflow/tempo` | Retorna o tempo que a visita da assistência passou em cada situação. | 1 | 10 | não |

### Atendimentos

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `atendimentos/times/integrantes` | Retorna os integrantes dos times de atendimentos | 22 | 10 | não |
| `atendimentos/times` | Retorna os times de atendimentos | 4 | 13 | não |
| `atendimentos/tarefas` | Retorna as tarefas dos atendimentos | 12 | 32 | não |
| `atendimentos/respostas` | Retorna as respostas dos atendimentos | 442 | 20 | não |
| `atendimentos/interacoes` | Retorna as interações dos atendimentos | 162 | 12 | não |
| `atendimentos/workflow/tempo` | Retorna o tempo que o atendimento passou em cada situação. | 2.735 | 10 | `atendimentos_workflow_tempo` |
| `atendimentos` | Retorna os dados dos atendimentos | 837 | 60 | `atendimentos_cvcrm` |
| `atendimentos/workflow-tempo` | Retorna atendimentos workflow tempo | 2.735 | 10 | não |

### Leads

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `leads/corretores` | Retorna os dados do corretor do lead | 79.902 | 10 | não |
| `leads` | Retorna os dados dos leads | 58.963 | 76 | `leads` |
| `leads/conversoes` | Retorna os dados das conversões dos leads | 260.517 | 22 | `leads_conversoes` |
| `leads/ganhos` | Retorna os dados dos leads ganhos | 2.507 | 11 | não |
| `leads/historico/situacoes` | Retorna o histórico das situações dos leads | 199.982 | 14 | não |
| `leads/infos` | Retorna alguns dados dos leads | 58.963 | 9 | `leads_infos` |
| `leads/interacoes` | Retorna a listagem de interações dos leads. | 155.124 | 24 | não |
| `leads/momentos` | Retorna os dados dos momentos dos leads | 0 | - | não |
| `leads/perdas` | Retorna as informações de perda do leads | 21.460 | 11 | não |
| `leads/tarefas` | Retorna as tarefas dos leads | 13.689 | 23 | não |
| `leads/visitas` | Retorna a listagem de interações de visitas de leads. | 1.294 | 24 | não |
| `leads/workflow/tempo` | Retorna o tempo em que o lead passou em determinada situação. | 197.024 | 10 | não |
| `leads/possibilidade` | Retorna as alterações na possibilidade de vendas dos leads. | 103 | 13 | não |

### Filas de Distribuição

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `distribuicao/leads` | Retorna a distribuição dos leads | 5.200 | 24 | não |

### Usuários Administrativos

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `usuarios_administrativos` | Retorna os dados dos usuários administrativos | 211 | 17 | não |

### Processos

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `processos` | Retorna os dados dos processos | 0 | - | não |

### Pre-cadastro

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `precadastros` | Retorna os dados dos pré-cadastros | 6.652 | 53 | `precadastros` |
| `precadastro/workflow/tempo` | Retorna o tempo do pré-cadastro em cada situação | 53.503 | 10 | não |
| `precadastro/historico/situacoes` | Retorna o histórico de situações do pré-cadastro | 60.055 | 12 | `precadastro_historico_situacoes` |

### Imobiliarias

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `imobiliarias` | Retorna os dados das imobiliarias | 640 | 58 | `imobiliarias` |

### Corretores

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `corretores` | Retorna os dados dos corretores | 1.099 | 108 | `corretores` |

### Pesquisas

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `pesquisas` | Retorna as pesquisas ativas | 10 | 11 | não |
| `pesquisas/perguntas` | Retorna as perguntas das pesquisas | 74 | 9 | não |
| `pesquisas/respostas` | Retorna as respostas das pesquisas | 201 | 10 | não |

### Repasses

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `repasses` | Retorna os dados dos repasses | 3.440 | 63 | `repasses` |
| `repasses/workflow/tempo` | Retorna o tempo que o repasse ficou em uma determinada situação. | 31.112 | 10 | `repasses_workflow_tempo` |
| `repasses/historico/situacoes` | Retorna o histórico das situações do repasse | 31.782 | 14 | `repasses_historico_situacoes` |

### Campanhas de Ativação

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `campanhas_ativacao` | Retorna as campanhas de ativação | 348 | 31 | não |

### Campos Adicionais

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `campos_adicionais` | Retorna os campos adicionais | 243.067 | 10 | `campos_adicionais` |

### Pessoas

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `pessoas` | Retorna os dados das pessoas | 8.568 | 92 | `pessoas` |
| `pessoas/contatos` | Retorna os dados de contatos das pessoas | 8.568 | 29 | não |
| `pessoas/profissional` | Retorna os dados profissionais e outras rendas das pessoas | 8.568 | 51 | `pessoas_profissional` |
| `pessoas/patrimoniais` | Retorna os dados patrimoniais das pessoas | 8.568 | 11 | não |
| `pessoas/bancarios` | Retorna os dados bancários das pessoas | 8.568 | 15 | não |
| `pessoas/bens-empresa` | Retorna os bens da empresa das pessoas | 0 | - | não |
| `pessoas/financeiros` | Retorna os dados financeiros das pessoas | 8.568 | 32 | não |
| `pessoas/tag_associadas` | Retorna as tags associadas a pessoa | 973 | 7 | não |

### Correspondentes

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `correspondentes-usuarios` | Retorna os usuários correspondentes | 30 | 15 | não |
| `correspondentes-empresas` | Retorna as empresas correspondentes | 7 | 12 | não |

### Assistências Técnicas

| Endpoint | O que devolve | Registros | Campos | Ingestão |
|---|---|---:|---:|---|
| `assistencias/itens/workflow-tempo` | Retorna itens workflow tempo | 0 | - | não |
| `assistencias/visitas/workflow-tempo` | Retorna visitas workflow tempo | 1 | 10 | não |
| `assistencias/workflow-tempo` | Retorna assistencias workflow tempo | 6 | 10 | não |

## Endpoints que não responderam

- `reservas/sienge`: erro. HTTP 422 em https://pafil.cvcrm.com.br/api/v1/cvdw/reservas/sienge: {"error":"Ocorreu um e
- `v2/cvdw/agendamentos/vistorias`: erro. HTTP 405 em https://pafil.cvcrm.com.br/api/v1/cvdw/v2/cvdw/agendamentos/vistorias: {"error A referência mistura o servidor /api/v1/cvdw com um caminho /vN/...: o endpoint equivalente costuma estar na lista acima, sem o prefixo.
