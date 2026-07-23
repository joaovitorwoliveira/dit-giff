# Prompt — protótipo da tela principal (Claude Design)

Tipo de projeto: **Prototype**. Importe `docs/product/DESIGN-SYSTEM.md` como design
system antes de rodar isto — todas as cores, tipografia e espaçamentos vêm de lá e não
devem ser reinventados aqui.

---

Projete a tela principal do Dit Giff, um app nativo de macOS.

## O produto em três linhas

Dit Giff pega o diff entre uma branch e sua branch-base, monta localmente a partir do
git da máquina, e te ajuda a ENTENDER a mudança antes de abrir o merge request. Ele
não revisa por você. Ele te faz ler mais rápido e te deixa pronto pra defender cada
decisão quando o revisor perguntar "por que isso?".

## Quem usa e em que momento exato

Um dev que trabalha com agentes de IA. Implementar ficou barato: uma feature de uma
semana sai em 3 horas. O gargalo agora é a revisão. Caso real que originou o produto:
código 95% pronto em 2 horas, e 4 DIAS até abrir o MR — travado no medo de o revisor
perguntar "por que essa decisão?" e não saber responder.

O momento de uso é esse: o código está pronto, o MR não foi aberto, e a pessoa precisa
entender o que o agente escreveu. Ela abre o Dit Giff no lugar de abrir a aba de
"Changes" do GitLab.

## O benchmark a bater

A tela de diff do GitLab/GitHub. Os quatro problemas dela que você precisa resolver:

1. 64 arquivos numa lista plana e você se afoga. Não existe visão macro do que a
   mudança FAZ — só de quais arquivos ela tocou.
2. Ruído tratado igual a sinal: lockfile, arquivo gerado, mudança só de formatação,
   arquivo renomeado sem alteração — tudo ocupa o mesmo espaço que a lógica de negócio
   que realmente mudou.
3. A navegação é linear por arquivo, mas o entendimento é conceitual. Uma mudança
   atravessa 6 arquivos e você tem que remontar isso de cabeça.
4. Nada registra o que você já leu e entendeu.

## A tela: três painéis

### Painel esquerdo — o mapa da mudança

NÃO é uma árvore de arquivos. É a mudança agrupada por INTENÇÃO. O topo diz, em
linguagem natural, o que este MR faz, em 2 a 4 grupos nomeados:

    1. Cobrança passa a considerar plano anual   — 7 arquivos
    2. Migração do cliente HTTP antigo           — 12 arquivos
    3. Testes de regressão                       — 9 arquivos

Cada grupo abre e mostra seus arquivos. Um arquivo pode aparecer em mais de um grupo.

Abaixo dos grupos, uma seção separada e COLAPSADA POR PADRÃO chamada "Ruído", com
contagem: lockfiles, arquivos gerados, mudanças só de whitespace, renomes puros. Uma
linha cada, expansível.

O topo do painel mostra o par branch → base, e um indicador de progresso de leitura
("18 de 47 hunks lidos").

### Painel central — o diff

Diff unificado, syntax highlight, verde e coral do design system. Cada hunk é uma
unidade visual com borda sutil e cabeçalho discreto. No hover do hunk aparecem duas
ações: "Explicar" e "Marcar como lido".

Hunks já lidos ficam visualmente recuados — opacidade menor, ou colapsados numa linha
de resumo. Hunks com pista da IA anexada mostram um marcador discreto na margem.

### Painel direito — as pistas

Aqui vive a saída da IA. REGRA INEGOCIÁVEL: pistas, nunca vereditos. O painel jamais
diz "BUG ENCONTRADO" ou "isso está errado". Ele diz o que um revisor atento notaria,
em forma de observação ou pergunta. O humano decide. Três seções:

- **"Olha isso"** — trechos que parecem incidentais, fora do escopo do MR, ou mexidos
  por engano.
- **"Decisões a defender"** — as escolhas que um revisor vai questionar, escritas como
  a pergunta que ele faria.
- **"Explicações"** — respostas sob demanda, empilhadas, quando você clica "Explicar"
  num hunk.

Cada item é clicável e leva ao hunk correspondente no painel central, destacando-o.

## Estado inicial e um campo opcional

Antes de rodar a análise existe um campo de texto opcional e discreto, com o
placeholder "O que essa mudança deveria fazer? (opcional)". Uma frase do usuário deixa
a IA mais precisa. Nunca é obrigatório e nunca bloqueia nada.

## Popule com estes dados — não use lorem ipsum

Cenário real que originou o produto:

    Branch: feature/annual-billing → main
    64 arquivos, +3242 / −347

    Pista 1 (Olha isso): "O check de cobrança em BillingGuard.swift:142 mudou de
    `>=` pra `>`. Contas exatamente no limite do plano agora caem no outro lado.
    Foi intencional?"

    Pista 2 (Olha isso): "resolvePlan() antes retornava nil quando não achava o
    plano; agora lança exceção. Três chamadores no diff tratam o retorno, nenhum
    captura a exceção."

    Pista 3 (Decisão a defender): "Por que a validação foi movida do handler pro
    model? O revisor vai perguntar se isso muda a ordem dos erros retornados pela
    API."

    Ruído: 4 arquivos (Package.resolved, 2 snapshots gerados, 1 arquivo só
    reindentado)

O código no painel central é Swift real e plausível — `BillingGuard.swift`,
`resolvePlan()`, os chamadores. As pistas precisam apontar para linhas que existem de
verdade no diff mostrado.

## É um app nativo, não um web app

Isso muda decisões concretas:

- Sidebar translúcida à esquerda, toolbar unificada no topo com os controles de
  branch. Sem barra de navegação de browser, sem breadcrumb de site, sem footer.
- Densidade alta mas respirável. O conforto de ler 3000 linhas importa mais do que
  impressionar na primeira tela.
- Light e dark mode, ambos funcionando de verdade — não um filtro invertido.

## Interatividade a entregar

Navegável de verdade: expandir e colapsar grupos, expandir a seção "Ruído", marcar
hunk como lido (com o contador de progresso reagindo), clicar numa pista e pular para
o hunk correspondente com destaque, alternar light e dark. Sem backend, dados fixos.

## Entregue também

Depois da tela cheia, três estados que definem o produto tanto quanto ela:

1. **Antes da análise** — o campo opcional, o par de branches escolhido, nada de
   pistas ainda.
2. **Tudo lido** — todos os hunks recuados, o progresso completo. É o estado de
   sucesso do produto, o momento "posso abrir o MR".
3. **Painel de pistas vazio** — a IA não achou nada digno de nota. Precisa parecer um
   resultado legítimo e tranquilizador, nunca uma falha ou um vazio abandonado.
