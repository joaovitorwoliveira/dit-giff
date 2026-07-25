# Dit Giff — design system

Este é o arquivo a importar no Claude Design antes de gerar qualquer tela. Tudo aqui
deriva das decisões já tomadas no ícone (`assets/icon/`), estendidas para o que uma
interface de leitura longa precisa.

## A ideia que atravessa tudo

Duas decisões do ícone valem para a interface inteira:

**Nenhum cinza é neutro.** Todo preto, todo cinza e todo branco desta interface tem
undertone verde. É quase imperceptível isolado, e é o que faz a tela parecer feita por
alguém em vez de montada com o cinza padrão do framework. Se um tom aparecer neutro,
está errado.

**A divisa antes/depois.** O ícone é um campo partido em dois. A interface pode ecoar
isso, mas com parcimônia — na divisa entre painéis, nunca como decoração.

## Cor

Todos os valores em sRGB.

### Superfícies — dark (o modo padrão)

| Token | Hex | Uso |
| --- | --- | --- |
| `surface-0` | `#0B120F` | fundo da janela, o nível mais fundo |
| `surface-1` | `#0F1714` | painéis, sidebar |
| `surface-2` | `#141D19` | blocos de hunk, cards elevados |
| `surface-3` | `#1A2420` | hover, linha selecionada |
| `border-subtle` | `#1E2A25` | divisórias internas, borda de hunk |
| `border` | `#2A3832` | separação entre painéis |

### Superfícies — light

| Token | Hex | Uso |
| --- | --- | --- |
| `surface-0` | `#F2F5F3` | fundo da janela |
| `surface-1` | `#FAFCFB` | painéis |
| `surface-2` | `#FFFFFF` | blocos de hunk |
| `surface-3` | `#EDF2EF` | hover, seleção |
| `border-subtle` | `#E2E9E5` | divisórias internas |
| `border` | `#D3DDD8` | separação entre painéis |

### Texto

| Token | Dark | Light | Uso |
| --- | --- | --- | --- |
| `text-primary` | `#E4EDE8` | `#101815` | código, títulos |
| `text-secondary` | `#9CAEA5` | `#4F5F58` | rótulos, metadados |
| `text-tertiary` | `#66776F` | `#7C8B84` | números de linha, contagens |
| `text-error` | `#C97B88` | `#9A4554` | banner de erro, falha recuperável |

`text-error` é rosa-poeira / vinho — vermelho o bastante para marcar, mas **não** o
coral de `diff-del` (`#FF5744` no dark / `#E0230E` no light, na paleta Swift de
revisão 2). Erro e remoção lado a lado têm de ser distinguíveis; o mesmo vermelho
nas duas leituras deixaria a tela ambígua. Use só no texto do aviso, com sobriedade
— voz de colega atento, não alarme.

### Diff

As cores de marca vivem no gutter e no texto. Os fundos de linha são as mesmas cores
em alfa muito baixo — nunca cores próprias, para que verde e coral apareçam uma vez só
no sistema.

| Token | Dark | Light |
| --- | --- | --- |
| `diff-add` | `#8FBF8A` | `#3F7238` |
| `diff-del` | `#F07A64` | `#B8412A` |
| `diff-add-bg` | `#8FBF8A` @ 9% | `#3F7238` @ 8% |
| `diff-del-bg` | `#F07A64` @ 9% | `#B8412A` @ 8% |
| `diff-add-word` | `#8FBF8A` @ 22% | `#3F7238` @ 18% |
| `diff-del-word` | `#F07A64` @ 22% | `#B8412A` @ 18% |

`diff-add` e `diff-del` no dark são exatamente as cores do ícone. Essa repetição é
proposital: é o que amarra a marca à tela.

### Não existe cor de destaque separada

A tentação é criar um accent azul ou roxo para seleção e foco. Não faça. Seriam cinco
matizes numa tela que já tem duas com significado semântico forte, e o brief é
explícito: se tudo tem cor, nada tem.

- **Seleção**: `surface-3` mais uma régua de 2px em `diff-add` na borda esquerda.
- **Foco de teclado**: anel de 2px em `diff-add` a 40% de opacidade.
- **Link / ação**: `text-primary` com sublinhado, não uma cor.

O `diff-add` como cor de ação funciona porque em ferramenta de diff verde já significa
"presente, adicionado" — é a mesma semântica, não uma segunda.

## Tipografia

| Papel | Família | Tamanho / entrelinha | Peso |
| --- | --- | --- | --- |
| Título de painel | SF Pro Text | 13 / 18 | 600 |
| Corpo de interface | SF Pro Text | 13 / 18 | 400 |
| Rótulo, metadado | SF Pro Text | 11 / 15 | 500 |
| Código | SF Mono | 12 / 18 | 400 |
| Número de linha | SF Mono | 11 / 18 | 400 |

Em HTML: `-apple-system, BlinkMacSystemFont` para interface e `ui-monospace,
"SF Mono", Menlo` para código.

A entrelinha do código é 18px e não se mexe. É uma ferramenta de leitura longa: a
regularidade vertical do bloco de código importa mais do que economizar altura.

## Espaçamento, raio, elevação

Base de 4px. Use `4 8 12 16 24 32 48`, nada fora disso.

| Raio | Valor | Uso |
| --- | --- | --- |
| `radius-sm` | 6px | badges, chips, contadores |
| `radius-md` | 10px | blocos de hunk, cards de pista |
| `radius-lg` | 14px | popovers, painéis flutuantes |

Cantos macios em tudo, ecoando as pontas arredondadas do ícone. Nada de canto vivo.

Elevação por superfície, não por sombra. A única sombra da interface é a de popovers.

## Densidade

Alta mas respirável. Altura de linha em listas: 28px. Padding interno de painel: 12px.
Gutter do diff: 44px de largura.

## Movimento

Só o que confirma uma ação: expandir e colapsar grupos (160ms, ease-out), marcar hunk
como lido (200ms de fade para o estado recuado), pular para um hunk (scroll suave de
240ms mais um flash de destaque de 600ms). Nada mais anima. Sem parallax, sem entrada
escalonada, sem skeleton pulsante.

## Restrição que vem do destino final

Este design vai ser reimplementado em SwiftUI. Prefira estruturas que mapeiam direto
para `NavigationSplitView`, `List`, `ScrollView` e `HSplitView`. Evite qualquer coisa
que só exista em CSS — grid areas complexas, `backdrop-filter` empilhado,
posicionamento sticky aninhado. Se um detalhe visual for difícil de reproduzir
nativamente, escolha a versão mais simples.

## Proibido

Nenhum clichê de IA: sem gradiente roxo, sem ícone de faísca, sem estrelinha, sem
brilho pulsante em nada gerado por modelo. Sem cor saturada fora do verde e do coral
do diff — com a única exceção semântica de `text-error`, que é rosa/vinho de propósito
para não colidir com `diff-del`. Sem sombra pesada. Sem emoji na interface.
