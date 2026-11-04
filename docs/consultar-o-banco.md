# Consultando o banco

Passo a passo para explorar as camadas bronze, silver e gold, seja num banco local de
desenvolvimento, seja na produção por túnel SSH (somente leitura, de preferência).

## 1. Conectar

Pelo atalho `ferramentas/consultar.ps1`, que lê as variáveis `PG_*` do `.env`:

```powershell
.\ferramentas\consultar.ps1                      # abre uma sessão psql interativa
.\ferramentas\consultar.ps1 -c "SELECT 1"        # roda um comando e sai
.\ferramentas\consultar.ps1 -c "\dt silver.*"    # qualquer opção do psql pode ser repassada
```

Para um cliente gráfico (DBeaver, pgAdmin), use os mesmos dados do `.env`:

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Porta | A do `PG_PORT` do seu `.env` (`5433` no túnel de produção, `5432` num Postgres instalado normalmente) |
| Banco | `pafil_dw` |
| Usuário | Em produção, `pafil_bi` para ler (silver e gold) ou `pafil_app` para carga e DDL |
| Senha | A do seu `.env`. As de produção ficam na máquina do banco, e não neste repositório |
| SSL | Desabilitado (`disable`), porque o tráfego não sai da sua máquina |

Se for consultar a produção, abra antes o túnel SSH (veja
[`infra/README.md`](../infra/README.md)) e confirme em qual banco você caiu:

```sql
SELECT current_database(), inet_server_addr();
```

## 2. Explorar o catálogo com o psql

```
\dn                     -- lista os schemas (bronze, silver, gold e os dos projetos vizinhos)
\dt bronze.*            -- tabelas da bronze
\dv silver.*            -- views da silver
\dt silver.*            -- tabelas (de-paras) da silver
\dv gold.*              -- views da gold
\d+ gold.fato_reservas  -- colunas e tipos de um objeto
\df silver.*            -- funções (tentar_timestamptz, conformar_empreendimento, nome_proprio...)
```

## 3. O que existe em cada schema

- **`bronze`**: uma tabela crua por objeto (CVCRM, Blip e MDnet), mais uma `_snapshot` para
  cada uma e a tabela de controle `_ingestao_controle`, que guarda a última execução e o
  status de cada carga.
- **`silver`**: views conformadas (`reservas`, `vendas`, `distratos`, `unidades`,
  `corretores`, `imobiliarias`, `leads`, `precadastros`, as de atendimento e as de telefonia)
  e as tabelas de-para (`dpara_*`, entre elas `dpara_gerente_contexto`,
  `dpara_corretor_headcount` e `dpara_canal_midia`).
- **`gold`**: fatos (`fato_reservas`, `fato_leads`, `fato_precadastros`,
  `fato_atendimentos`, `fato_atendimentos_cvcrm`, `fato_chamadas`, `fato_headcount_mensal`) e
  dimensões (`dim_calendario`, `dim_empreendimento`, `dim_unidade`, `dim_corretor`,
  `dim_origem` e outras). A lista completa e o desenho estão em
  [`modelo-semantico.md`](modelo-semantico.md). Fora do modelo do Power BI existe a view de
  relatório `gold.vendas_atualizada` (uma reserva por linha, com planta e espaço
  complementar), que alimenta a planilha Vendas Atualizada via Power Query no Excel.

## 4. Consultas de exemplo

**Bronze** (o dado cru, como vem da API):

```sql
SELECT idreserva, situacao, valor_contrato, data_venda FROM bronze.reservas LIMIT 10;
SELECT count(*) FROM bronze.reservas;
```

**Silver** (conformado, com as flags de cada regra):

```sql
-- distribuição de situação com as flags da regra R1 (a dupla definição de "venda")
SELECT situacao, count(*),
       count(*) FILTER (WHERE eh_venda)    AS vendas,
       count(*) FILTER (WHERE eh_distrato) AS distratos
FROM silver.reservas GROUP BY situacao ORDER BY 2 DESC;

-- de-paras de gerente e de equipe do corretor
SELECT * FROM silver.dpara_gerente_contexto;
SELECT * FROM silver.dpara_corretor_headcount;

-- normalização de nome de pessoa: forma de exibição e chave de junção
SELECT silver.nome_proprio('MAISA CRISTINA DE PAULA E SILVA');  -- Maisa Cristina de Paula e Silva
SELECT silver.chave_nome('Estéfane Vitória Alves de Souza');    -- estefane vitoria alves de souza
```

**Gold** (fatos e dimensões; agregações mais elaboradas ficam no Power BI):

```sql
-- total geral, direto na fato
SELECT round(sum(valor_contrato) FILTER (WHERE eh_venda))    AS vgv_bruto,
       count(*)                   FILTER (WHERE eh_venda)     AS qtd,
       round(sum(valor_contrato)  FILTER (WHERE eh_distrato)) AS vgv_distrato
FROM gold.fato_reservas;

-- VGV por mês e por empreendimento (nome já conformado)
SELECT ano_mes_venda, empreendimento_conformado,
       count(*) qtd, round(sum(valor_contrato)) vgv
FROM gold.fato_reservas
WHERE eh_venda AND ano_mes_venda >= '2026-01'
GROUP BY ano_mes_venda, empreendimento_conformado
ORDER BY ano_mes_venda DESC, vgv DESC;
```

**Conferir se as cargas estão rodando** (vale para Blip e MDnet também):

```sql
SELECT nome_logico, ultima_execucao, ultimo_modo, registros_ultima_carga, status, mensagem
FROM bronze._ingestao_controle
ORDER BY ultima_execucao DESC;
```

O que olhar: `status` igual a `OK` e `ultima_execucao` de hoje.

## 5. Dicas do psql

- `\x on` liga o modo expandido, útil para tabelas largas como `bronze.reservas`, que tem
  cerca de 90 colunas.
- `\timing on` mostra quanto cada consulta levou.
- `\o saida.txt` manda o resultado das próximas consultas para um arquivo. Para voltar ao
  console, digite `\o` sozinho.
- `\copy (SELECT ...) TO 'arquivo.csv' CSV HEADER` exporta o resultado para CSV. Lembre que
  CSV com dado pessoal não pode ir para o repositório.
- `\q` sai.
