# Onboarding: do zero até a primeira consulta

Para quem está pegando o projeto pela primeira vez, ou montando uma máquina nova. O guia
assume Windows com PowerShell, que é o ambiente do projeto. Os passos de Python e Postgres
valem também para Linux e macOS, com ajustes de caminho.

## 1. Clonar e montar o ambiente

```powershell
git clone https://github.com/arturvillasboas/data-hub-pafil.git
cd data-hub-pafil
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## 2. Preencher o `.env`

```powershell
Copy-Item .env.example .env
```

Edite o `.env` com os valores reais. De onde vem cada um:

| Variável | De onde vem |
|---|---|
| `CVCRM_SUBDOMINIO`, `CVCRM_EMAIL`, `CVCRM_TOKEN` | Peça um token de API ao administrador do CVCRM (o subdomínio é `pafil`). Nunca reaproveite um token que já circulou fora de um `.env`: gere um novo |
| `BLIP_*` | Chave do bot Router, no portal do Blip. O `.env.example` explica onde achar |
| `MDNET_*` | Usuário e senha do painel da MDnet |
| `PG_*` | Depende de qual banco você vai usar. Veja a seção 3 |
| `DEPARA_*`, `*_XLSX`, `*_XLSM`, `VENDAS_CONSOLIDADAS_XLSM` | Caminhos para planilhas do SharePoint do time Comercial, sincronizadas pelo OneDrive na sua máquina. Peça acesso à pasta "BI - Comercial" ao time comercial ou ao backoffice. A lista completa está em [`de-paras.md`](de-paras.md) |

Sem as planilhas configuradas, bronze, silver e gold funcionam normalmente. Só as tabelas de
de-para ficam vazias ou desatualizadas, o que não impede de começar a explorar.

## 3. Escolher um banco

### Opção A: banco local de desenvolvimento

É a mais segura para testar mudanças de SQL. Instale o PostgreSQL 16 (instalador oficial da
EnterpriseDB), crie um banco chamado `pafil_dw` e aponte o `.env` para ele:

```
PG_HOST=localhost
PG_PORT=5432
PG_DB=pafil_dw
PG_USER=postgres
PG_PASSWORD=<a senha que você definiu na instalação>
PG_SSLMODE=disable
```

Sem permissão de administrador, dá para criar uma instância só do seu usuário, sem serviço do
Windows, e usar uma porta diferente para não colidir com outro Postgres da máquina:

```powershell
$bin  = "C:\Program Files\PostgreSQL\16\bin"        # ajuste se a versão for outra
$data = "$env:LOCALAPPDATA\pafil_pg\data"
& "$bin\initdb.exe" -D $data -U postgres -A scram-sha-256 --pwfile=<arquivo-com-a-senha> -E UTF8
Add-Content "$data\postgresql.conf" "`nport = 5433"
& "$bin\pg_ctl.exe" start -D $data
```

Essa instância cai a cada logoff, porque é um processo comum do seu usuário. Para um banco
sem atrito, prefira a instalação normal.

### Opção B: banco de produção, por túnel SSH

Para consultar ou rodar os de-paras. O banco nunca é exposto à internet, então você abre um
túnel até a máquina de produção. Os detalhes (chave SSH, alias, IP liberado) estão em
[`infra/README.md`](../infra/README.md), seção "Acesso do analista ao banco". Com o túnel
aberto, o `.env` aponta para `localhost:5433`.

Cuidado: esse é o banco real, com dado pessoal de cliente. Não faça ali nada destrutivo. A
forma mais segura de apontar para a produção é definir só usuário e senha na sessão do
PowerShell, sem editar o `.env`:

```powershell
$env:PG_USER = "pafil_app"; $env:PG_PASSWORD = "<senha, lida de dentro da máquina de produção>"
```

Antes de qualquer carga, confirme em qual banco você caiu:

```powershell
psql -h localhost -p 5433 -c "select current_database(), inet_server_addr()"
```

## 4. Construir o banco

```powershell
python criar_database.py                    # cria o banco, se não existir
python ingestao.py --full --criar-tabelas   # aplica a bronze e faz a carga completa do CVCRM
python aplicar_tudo.py                      # silver, gold e seeds
```

A carga completa leva horas, porque a API aceita cerca de 18 requisições por minuto. Em banco
local, vale limitar a poucos objetos: `python ingestao.py --full --criar-tabelas --objetos reservas,distratos`.

Blip e MDnet têm cargas próprias (`ingerir_blip.py`, `ingerir_mdnet.py` e as duas irmãs, veja
[`infra/README.md`](../infra/README.md)). Para a primeira instalação da MDnet:

```powershell
python ingerir_mdnet.py --criar-tabelas --full
python ingerir_mdnet_pernas.py --full
python ingerir_mdnet_ura.py --full
python aplicar_silver.py --so-mdnet
```

Nas vezes seguintes basta `python ingestao.py --incremental`. Silver e gold são views, então
refletem a novidade na hora.

## 5. Conferir

```powershell
python conferir_carga.py                                  # total da API contra o total da bronze, objeto a objeto
.\ferramentas\consultar.ps1 -c "SELECT count(*) FROM gold.fato_reservas"
```

O guia de exploração do banco, com exemplos por camada, está em
[`consultar-o-banco.md`](consultar-o-banco.md).

## 6. O que ler em seguida

1. [`contexto.md`](contexto.md): o porquê do projeto, o que existe e o que falta.
2. [`arquitetura.md`](arquitetura.md): a visão técnica e onde cada coisa roda.
3. [`modelo-semantico.md`](modelo-semantico.md): o desenho do modelo em estrela da gold.
4. [`regras-de-negocio.md`](regras-de-negocio.md): as regras herdadas dos relatórios antigos.
5. [`de-paras.md`](de-paras.md): quais são os mapeamentos manuais e como recarregar cada um.
6. [`decisoes.md`](decisoes.md): o que já foi decidido e não deve ser reaberto sem motivo.
