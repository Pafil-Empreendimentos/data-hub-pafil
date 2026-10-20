# Decisões fechadas, segurança e LGPD

Este documento guarda o que já foi decidido e o motivo, para ninguém reabrir uma discussão
sem saber por que ela foi encerrada. Se surgir um motivo concreto para mudar algo daqui,
mude e registre a nova decisão na tabela, com data.

## 1. Decisões de arquitetura

| Tema | Decisão | Por quê |
|---|---|---|
| Banco | PostgreSQL, software livre | Requisito fixo do projeto: engine portável, sem dependência de fornecedor |
| Onde o banco roda | Máquina Windows 10 Pro da empresa, acesso por RDP, Postgres 16 como serviço do Windows, em produção desde 20/ago/2026 | A infraestrutura precisa ser da Pafil, sem risco de ser cortada por falta de pagamento de uma pessoa. Veja o histórico na seção 2 |
| Arquitetura de dados | Medalhão: bronze, silver e gold | A bronze fica o mais perto possível da origem, sem regra de negócio. A silver limpa, padroniza e conforma. A gold entrega fatos e dimensões com os indicadores oficiais |
| Migração do BI antigo | Estrangulamento gradual: as extrações dos PBIX antigos seguem rodando em paralelo até a reconciliação número a número confirmar a plataforma nova | Troca o sistema sem virada brusca, com os dois convivendo até a troca ser segura |
| Relatório | Power BI Pro. O Power BI Service lê o banco por um On-premises Data Gateway instalado na própria máquina do banco | O banco nunca é exposto à internet |
| Transformações | dbt-core, adotado em 15/set/2026. **Ainda não implementado** | O schema estabilizou, e a falta de teste automatizado virou risco de sucessão |
| Agendamento | Airflow, adotado em 15/set/2026. **Ainda não implementado**: hoje roda no Agendador de Tarefas do Windows | A máquina de produção acumula operação manual via PowerShell, e existe um segundo projeto (integração com o GoHighLevel) que também precisa de agendamento visível |
| Ordem de execução | A integração CVCRM e GHL vem primeiro, sobre SQL simples no Postgres e o agendador do próprio n8n. A migração para dbt e Airflow vem depois, e a lógica da integração é incorporada a ela numa fase própria | Pedido da gestão |
| Dados de de-para | Continuam manuais, rodados do notebook do analista por túnel SSH | As planilhas de origem são mantidas à mão pelo backoffice e só existem sincronizadas na máquina de quem as edita. Veja [`arquitetura.md`](arquitetura.md) |

**Opções descartadas de propósito:** Neon, Supabase e qualquer serviço de terceiros ou
infraestrutura pessoal para o banco. O banco guarda dado pessoal de cliente (LGPD) e não pode
dividir ambiente com automações pessoais de ninguém.

## 2. Histórico da hospedagem

O banco passou por três decisões, e as duas primeiras ficaram só no papel:

1. Um VPS na DigitalOcean (Linux). Descartado quando a gestão pediu para não depender de
   infraestrutura pessoal.
2. Uma instância AWS EC2 (Linux), decidida em 7/ago/2026 por causa de um licenciamento
   corporativo já existente. A TI nunca a provisionou.
3. **Decisão final, em 20/ago/2026:** a TI passou credenciais de RDP para uma máquina Windows
   10 Pro física, já em uso, e confirmou que ela é o destino definitivo. Não é uma instância
   AWS: o endereço de metadados da AWS não responde nela. Também não existem Security Group,
   disco gerenciado nem snapshot automático por trás dela. Por isso o firewall do Windows é a
   principal defesa de rede e o backup diário é a única proteção contra perda de disco.

Os scripts e documentos da versão Linux foram removidos do repositório e continuam no
histórico do Git, caso a empresa mude para uma instância Linux no futuro. Um Postgres
gerenciado (RDS ou Azure Database) segue como opção para o futuro, e o gatilho para migrar
seria operar o banco por conta própria pesar mais do que o custo do serviço.

## 3. Segurança e LGPD

- Os dados incluem dado pessoal real de clientes (entidades `leads` e `pessoas`). O banco só
  pode existir em infraestrutura da própria empresa, nunca em conta pessoal, camada gratuita
  de terceiros ou dividindo ambiente com um fluxo pessoal.
- Um Postgres próprio significa que a equipe é a responsável por backup, patches, firewall e
  monitoramento.
- A porta 5432 nunca é liberada para fora da máquina. O acesso do analista é por túnel SSH.
- O GitHub Actions não consegue alcançar o banco (runners têm IP dinâmico numa faixa pública
  enorme), por isso a ingestão roda dentro da máquina de produção. O antigo workflow de
  Actions foi removido.
- O papel `pafil_app` é dono do banco (ingestão e DDL). O papel `pafil_bi` é somente leitura
  nas camadas silver e gold, e não enxerga a bronze, onde o dado pessoal ainda está bruto.
- Token e e-mail da API nunca vão para o repositório: ficam no `.env`, com o
  `.env.example` versionado como modelo.
- Telefone, e-mail e CPF de cliente não entram no repositório em nenhum formato (CSV,
  planilha, print). O mesmo vale para dados de destinatários de relatórios.

### Onde cada segredo mora

| Segredo | Onde mora | Nunca vai para |
|---|---|---|
| `CVCRM_TOKEN`, `CVCRM_EMAIL` | `.env` do notebook e `.env` da máquina de produção | O repositório, logs, mensagens ou prints |
| Senhas do banco de produção | Geradas na própria máquina, em arquivo com acesso restrito aos administradores. Para o túnel do analista, entram como variável de ambiente da sessão e não são gravadas no `.env` | O repositório |
| Credenciais do Blip e da MDnet | `.env` da máquina de produção | O repositório |
| Caminhos das planilhas (`DEPARA_*`) | `.env` de cada máquina. Não são segredo, mas mudam de máquina para máquina | O `.env.example`, que usa placeholder |

### Rotação do token do CVCRM

Rotacione o `CVCRM_TOKEN` quando:

1. ele tiver circulado fora do `.env` (chat, e-mail ou print de tela);
2. alguém com acesso ao `.env` sair do time;
3. por rotina, pelo menos uma vez por ano.

Para rotacionar: gere um token novo no painel do CVCRM, atualize o `.env` do notebook e o da
máquina de produção, e confirme que a próxima execução agendada passou sem erro.

### Clones e dado local

Dado pessoal real só deve existir na infraestrutura da empresa ou, enquanto for necessário
para o trabalho, no banco local de desenvolvimento. Não deixe clones esquecidos com a carga
completa em notebooks além do que o trabalho exige.

### Visibilidade do repositório

Este repositório descreve a operação interna da empresa (regras de negócio, topologia de
infraestrutura, nomes de planilhas e relatórios). Ele deve ser **privado**. Se algum dia for
aberto, revise antes o conteúdo de `powerbi/de_para_classificacao.xlsx`, de
`reconciliacao/` e os nomes de máquinas e caminhos citados em `infra/`.
