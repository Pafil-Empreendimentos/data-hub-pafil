# Capa e contra capa de navegação

Duas artes em SVG (1280x720, o mesmo tamanho de uma página 16:9 do Power BI) para
a navegação do `.pbix` da reestruturação.

| Arquivo | O que é |
|---|---|
| `capa.svg` | Tela de entrada. Quatro cards, um por departamento: Comercial, Marketing, Relacionamento e Crédito. |
| `contracapa.svg` | Índice de páginas. Um painel por departamento, listando as páginas daquele departamento com uma linha de descrição. |

## Paleta e logo

Extraídos de `Reunião Pafil Regionais - Julho 26.pptx` (a apresentação mensal de
fechamento):

- Fundo navy em gradiente: `#0E4C8C` para `#073266` para `#04142A`
- Acento: ciano `#4CF4F2` para verde água `#16AF97`
- Texto e logo: branco `#FFFFFF`
- Fonte: Segoe UI Semibold

O logo "PAFIL EMPREENDIMENTOS" (versão branca) está embutido no SVG como imagem
base64, então o arquivo é autossuficiente.

## Como usar no Desktop

O SVG entra como imagem de fundo da página (Formatar página > Tela de fundo, ou um
visual de imstatica ocupando a página toda). O clique de verdade, que leva de uma
página para outra, é feito com botões nativos do Power BI por cima da arte, cada um
com ação de Navegação de página apontando para a página de destino. O desenho da
arte já reserva o espaço de cada card e de cada item da lista para esses botões
ficarem alinhados.

## Páginas por departamento

Espelha o que está no `.pbix` hoje. Se você renomear, adicionar ou mover uma
página entre departamentos, regenere os dois SVGs para não sair do ar.

- Comercial: Vendas Geral, Acompanhamento de Reservas, Preço por Produto, Performance
- Marketing: Marketing N1, Leads
- Relacionamento: Volumetria (Blip), Volumetria (CVCRM), Telefonia: Ligações e URA, Perfil do Cliente
- Crédito: Pré Cadastros

Observação: no painel de navegação a página está escrita como "Performace", sem o
"n". Nas artes ela aparece como "Performance".

Existem duas páginas de volumetria em Relacionamento, cada uma com uma fonte
diferente: "Volumetria (Blip)" é o atendimento via chat, sobre
`gold.fato_atendimentos` (ver `powerbi/PAGINA_ATENDIMENTO.md`). "Volumetria
(CVCRM)" é volume de contatos/interações que vem direto do CVCRM, não do Blip, e
ainda não tinha medidas nem página no repositório em 17/set/2026.

"Telefonia: Ligações e URA" é a página da central telefônica (PABX da MDnet): ligações
recebidas, ruído (robocall e spam), taxa de atendimento bruta e sem ruído, funil da
URA por opção de menu e atendidas por setor. As medidas e o guia estão em
`powerbi/MEDIDAS_TELEFONIA.dax` e `powerbi/PAGINA_TELEFONIA.md`. No `.pbix` a página
se chama só "Telefonia"; o nome da arte é mais específico de propósito, então vale
renomear a página no Desktop para ficar igual.
