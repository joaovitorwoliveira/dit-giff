# Atalhos de teclado

Referência do que o app trata por teclado, derivada do código. Se uma tecla
não faz nada, a pergunta útil é quase sempre: **qual superfície está com o
foco?**

---

## Foco: a regra que explica quase tudo

Os atalhos de uma letra (`j`, `k`, `n`, `v`) e a paginação do leitor
(`Space`, setas, `Page Up` / `Page Down`) só disparam quando o
`ScrollView` do leitor é o first responder. Isso está em
`DiffViewer` via `.focusable()` + `.focused(isFocused)` + `.onKeyPress`
(`DitGiff/DitGiff/Features/Diff/Views/Reader/DiffViewer.swift:70-73`).

O `FocusState` do leitor mora no shell (`DiffView`), não dentro do viewer
(`DitGiff/DitGiff/Features/Diff/Views/DiffView.swift:41-43`). O filtro da
sidebar e o composer do chat têm `FocusState` próprios. Digitar neles
nunca chega ao handler do leitor — o próprio código diz isso
(`DiffViewer.swift:95-97`).

### O que dá foco ao leitor

| Ação | Onde |
| --- | --- |
| Clique num arquivo na árvore da sidebar | `onFileRevealed` → `isReaderFocused = true` (`DiffView.swift:131`; clique em `DiffSidebarTree.swift:280-282`) |
| Toque (tap) na coluna do leitor | `isFocused.wrappedValue = true` (`DiffViewer.swift:83-84`) |
| Dismiss do banner de erro de reading progress | `isReaderFocused = true` (`DiffView.swift:145-147`) |

### O que tira o foco do leitor (e por que `j` “morre”)

- Clicar no **filtro** da sidebar: o `TextField` fica focado
  (`DiffSidebar.swift:134-150`). As letras vão para o filtro.
- Clicar no **composer** do chat: o `TextEditor` fica focado
  (`DiffChatPanel.swift:309-361`). As letras vão para o rascunho.
- Clicar no campo **Ask something specific…** do popover de seleção: o
  `TextField` fica focado (`DiffSelectionPopover.swift:10,65`).
- Controles com `dsFocusable` (botões da top bar, botões da Welcome)
  podem receber foco por Tab/`focusable`; enquanto um deles for o first
  responder, o leitor não recebe as teclas.

O botão de dismiss do banner de erro do leitor recusa foco de propósito
(`.focusable(false)` em `DiffView.swift:211-212`), para um clique nele
não roubar o first responder do `ScrollView`.

### O que o código não faz sozinho

`isReaderFocused` começa `false`. Não há `onAppear` / `defaultFocus`
colocando o foco no leitor ao abrir o diff. Sem um dos gestos da tabela
acima, `j` / `k` / `n` / `v` / `Space` não têm handler ativo — não é
bug do teclado.

O popover de seleção liga `.focused($isQuestionFocused)` ao campo, mas
**não** pede foco ao aparecer (sem `onAppear` nem `defaultFocus`). Se o
campo recebe foco automático do sistema ou não, **não foi verificado**
só lendo o código; o que o código garante é o `onSubmit` quando o campo
está focado.

---

## Leitor de diff

Superfície: coluna central (`DiffViewer`), com o `ScrollView` focado.

### Navegação entre arquivos (uma letra, sem modificador)

| Tecla | Faz | Atua quando | Não atua quando | Código |
| --- | --- | --- | --- | --- |
| `j` | Vai para o próximo arquivo na ordem do leitor (sem wrap no fim) | Leitor focado | Filtro, composer, ou outro first responder; com qualquer modificador o handler ignora | `DiffViewer.swift:100-102`; resolver em `DiffKeyboardNavigation.swift:28-39`; modelo em `DiffModel+Keyboard.swift:7-14` |
| `k` | Vai para o arquivo anterior (sem wrap no início) | Leitor focado | Idem | `DiffViewer.swift:103-105`; `DiffKeyboardNavigation.swift:42-53`; `DiffModel+Keyboard.swift:17-24` |
| `n` | Vai para o próximo arquivo não lido, com wrap a partir do topo; fica parado se todos já estão lidos | Leitor focado | Idem | `DiffViewer.swift:106-108`; `DiffKeyboardNavigation.swift:55-80`; `DiffModel+Keyboard.swift:27-49` |
| `v` | Alterna “viewed” no arquivo sob o cursor (`focusedFilePath`) | Leitor focado | Idem; se não há `focusedFilePath`, o modelo retorna sem efeito mas a tecla já foi consumida como `.handled` | `DiffViewer.swift:109-111`; `DiffModel+Keyboard.swift:52-55` |

Letras com modificador (ex.: `⇧j`, `⌘j`) caem em `.ignored`
(`DiffViewer.swift:98`).

### Rolagem dentro do arquivo

Não é a rolagem nativa do sistema. `.focusable()` instala um
`KeyViewProxy` como first responder, então o AppKit **não** pagina o
`ScrollView` sozinho; o app aplica um salto discreto em
`scrollPosition.scrollTo(y:)` (`DiffViewer.swift:33-35,144-151`).

O passo de página é `0.9 ×` altura do viewport; o de linha é
`DiffViewerMetric.codeLineHeight` (`20.15`)
(`DiffReaderKeyboardScroll.swift:51-74`; `DiffViewer.swift:230`).

| Tecla | Faz | Atua quando | Não atua / observação | Código |
| --- | --- | --- | --- | --- |
| `Space` | Página para baixo | Leitor focado; só Shift como modificador opcional | `⌘` / `⌥` / `⌃` + Space: mapeamento rejeita (`DiffViewer.swift:133-135`) | `DiffViewer.swift:120-121`; `DiffReaderKeyboardScroll.swift:31-32` |
| `⇧Space` | Página para cima | Leitor focado | Idem | `DiffViewer.swift:139-140`; `DiffReaderKeyboardScroll.swift:31-32` |
| `Page Down` | Página para baixo | Leitor focado, sem Shift | Com Shift o mapeamento devolve `nil` (não pagina) | `DiffViewer.swift:122-123`; `DiffReaderKeyboardScroll.swift:33-35` |
| `Page Up` | Página para cima | Leitor focado, sem Shift | Com Shift: idem, `nil` | `DiffViewer.swift:124-125`; `DiffReaderKeyboardScroll.swift:36-38` |
| `↓` | Uma linha para baixo | Leitor focado, sem Shift | Com Shift: `nil` | `DiffViewer.swift:126-127`; `DiffReaderKeyboardScroll.swift:39-41` |
| `↑` | Uma linha para cima | Leitor focado, sem Shift | Com Shift: `nil` | `DiffViewer.swift:128-129`; `DiffReaderKeyboardScroll.swift:42-44` |

Não há inércia, rubber-banding de trackpad, nem animação nesse caminho —
é um offset novo calculado e aplicado. `Home` / `End` / setas laterais
não entram no `switch` do mapeamento; o handler devolve `.ignored` para
elas. O que o sistema faz depois disso **não foi verificado** no código.

---

## Sidebar (mapa de mudanças)

### Filtro

O `TextField` “Filter files…” tem `@FocusState` e anel de foco
(`DiffSidebar.swift:131-159`). **Não há** `onKeyPress`, `onSubmit` nem
atalho próprio: digitar filtra via binding; Enter não tem ação especial
no código.

Enquanto o filtro está focado, os atalhos do leitor **não** rodam.

### Árvore

Clique num arquivo chama `revealFileInReader` e devolve o foco ao leitor
(`DiffSidebarTree.swift:280-282`). **Não há** tratamento de teclado
próprio na árvore (sem setas para navegar linhas, sem `j`/`k` na
sidebar).

---

## Chat

Superfície: `DiffChatPanel`, visível quando `model.isChatOpen`.

| Tecla | Faz | Atua quando | Não atua / observação | Código |
| --- | --- | --- | --- | --- |
| `Return` | Envia o rascunho do composer | Composer (`TextEditor`) focado e `isEnabled` (`model.canUseSampleAgent`) | Se o composer está desabilitado, `Return` é **consumido** (`.handled`) sem enviar — nada visível acontece | `DiffChatPanel.swift:374-381,333-337` |
| `⇧Return` | Nova linha no rascunho | Composer focado | O handler devolve `.ignored` para o `TextEditor` inserir a quebra | `DiffChatPanel.swift:376-378` |
| `Escape` (`onExitCommand`) | Fecha o chat (`closeChat`) | Registrado no painel inteiro | Se dispara com o `TextEditor` como first responder **não foi verificado** só pelo código; o modificador está em `DiffChatPanel`, não no composer | `DiffChatPanel.swift:32-34`; `DiffModel+Chat.swift:6-7` |

Não há atalho de teclado no código para **abrir** o chat; a abertura
passa por ações do modelo (envio, ask/explain da seleção, etc.).

Enquanto o composer está focado, `j` / `k` / `n` / `v` / `Space` do
leitor não disparam.

---

## Popover de seleção

Aparece sobre o hunk quando há seleção e há agente
(`DiffHunkBlock.swift:94-98`).

| Tecla | Faz | Atua quando | Código |
| --- | --- | --- | --- |
| `Return` (`onSubmit` do `TextField`) | Envia a pergunta da seleção (`askAboutSelection`) e limpa o campo | Campo “Ask something specific…” focado (e a linha habilitada por `canAskAboutSelection`) | `DiffSelectionPopover.swift:75,96-98` |

Não há `onKeyPress` no popover. Não há atalho de teclado no código para
“Explain selection” — só o botão.

---

## Welcome

O editor de goal é um `TextEditor` com `@FocusState` só para o anel de
foco (`WelcomeView.swift:515-562`). **Não há** `onKeyPress` /
`onSubmit` / atalho para “Open diff” a partir do teclado no editor.

Botões com `dsFocusable` (incluindo “Open diff”) podem ser ativados pelo
comportamento padrão de botão focado no macOS (`Space` / `Return` quando
o botão é o first responder). Isso é `dsFocusable` em
`DSModifiers.swift:43-86` + uso em `WelcomeView.swift:704` (e outros
botões da tela); **não** é um `keyboardShortcut` registrado pelo app.

---

## Top bar do diff

Toggle da sidebar, pill de branches (voltar) e toggle de tema usam
`dsFocusable` (`DiffTopBar.swift:77,113,184`). Sem
`keyboardShortcut`. Mesma regra: só respondem a tecla se o botão
estiver focado (comportamento de botão), não há atalho global.

---

## O que não existe (e frustra se você procura)

Confirmado no código:

1. **Não há barra de menu com atalhos do app.** `DitGiffApp` só declara
   `WindowGroup` + `.windowStyle(.hiddenTitleBar)`
   (`DitGiff/DitGiff/DitGiffApp.swift:10-22`). Não há `.commands`,
   `CommandGroup`, nem nenhum `keyboardShortcut` / `KeyEquivalent` no
   alvo da app (varredura em `DitGiff/DitGiff/**/*.swift`). O menu
   mínimo que o sistema possa mostrar sozinho **não foi inspecionado em
   runtime**.

2. **Rolagem por teclado no leitor é paginação discreta**, não a
   rolagem inercial nativa. Ver seção do leitor e o comentário em
   `DiffViewer.swift:33-35`.

3. **Não há** atalho global para abrir/fechar sidebar, abrir chat, voltar
   à Welcome, alternar tema, ou marcar hunk como lido — só o que as
   tabelas acima listam.

4. **Não há** monitor de `NSEvent` (`addLocalMonitor` /
   `addGlobalMonitor`) no app.

---

## Observações (conflitos / tecla consumida sem efeito)

- Com o leitor focado, `j` no último arquivo, `k` no primeiro, `n` com
  tudo lido e `v` sem `focusedFilePath` ainda retornam `.handled` no
  `onKeyPress` — a tecla é engolida mesmo quando o modelo não move nada
  (`DiffViewer.swift:99-111` + ramos `.stay` / `guard` no modelo).
- No composer desabilitado, `Return` é `.handled` sem enviar
  (`DiffChatPanel.swift:375`).
- `⇧Page Down` / `⇧Page Up` / `⇧↓` / `⇧↑` no leitor: o mapeamento
  devolve `nil` e o handler devolve `.ignored` — não paginam; o destino
  final da tecla **não foi verificado** além disso.
- Foco num botão `dsFocusable` da top bar (via Tab, por exemplo) tira o
  leitor do caminho dos atalhos de uma letra; `Space` nesse estado
  tenderia a ativar o botão (comportamento padrão de botão), não a
  paginar o diff. Interação exata Tab ↔ leitor **não foi verificada**
  em runtime.
