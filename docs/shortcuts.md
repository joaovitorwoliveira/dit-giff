# Atalhos de teclado

Referência do que o app trata por teclado, derivada do código. Se uma tecla
não faz nada, a pergunta útil é quase sempre: **qual superfície está com o
foco?**

---

## Foco: a regra que explica quase tudo

Os atalhos de uma letra (`n`, `v`), a navegação na árvore (setas esquerda /
direita), a navegação entre pastas (`⇧` + setas) e a paginação do leitor
(`Space`, setas cima / baixo, `Page Up` / `Page Down`) só disparam quando o
`ScrollView` do leitor é o first responder. Isso está em `DiffViewer` via
`.focusable()` + `.focused(isFocused)` + `.onKeyPress`
(`DitGiff/DitGiff/Features/Diff/Views/Reader/DiffViewer.swift`).

O `FocusState` do leitor mora no shell (`DiffView`), não dentro do viewer
(`DitGiff/DitGiff/Features/Diff/Views/DiffView.swift`). O filtro da sidebar e
o composer do chat têm `FocusState` próprios. Digitar neles nunca chega ao
handler do leitor — o próprio código diz isso (`DiffViewer.swift`).

### O que dá foco ao leitor

| Ação | Onde |
| --- | --- |
| Clique num arquivo na árvore da sidebar | `onFileRevealed` → `isReaderFocused = true` (`DiffView.swift`; clique em `DiffSidebarFileRow.swift`) |
| Toque (tap) na coluna do leitor | `isFocused.wrappedValue = true` (`DiffViewer.swift`) |
| Dismiss do banner de erro de reading progress | `isReaderFocused = true` (`DiffView.swift`) |

### O que tira o foco do leitor (e por que as letras “morrem”)

- Clicar no **filtro** da sidebar: o `TextField` fica focado
  (`DiffSidebar.swift`). As letras vão para o filtro.
- Clicar no **composer** do chat: o `TextEditor` fica focado
  (`DiffChatPanel.swift`). As letras vão para o rascunho.
- Clicar no campo **Ask something specific…** do popover de seleção: o
  `TextField` fica focado (`DiffSelectionPopover.swift`).
- Controles com `dsFocusable` (botões da top bar, botões da Welcome)
  podem receber foco por Tab/`focusable`; enquanto um deles for o first
  responder, o leitor não recebe as teclas.

O botão de dismiss do banner de erro do leitor recusa foco de propósito
(`.focusable(false)` em `DiffView.swift`), para um clique nele não roubar
o first responder do `ScrollView`.

### O que o código não faz sozinho

`isReaderFocused` começa `false`. Não há `onAppear` / `defaultFocus`
colocando o foco no leitor ao abrir o diff. Sem um dos gestos da tabela
acima, `→` / `←` / `⇧↓` / `n` / `v` / `Space` não têm handler ativo — não
é bug do teclado. Com o leitor focado e sem linha sob o cursor, `→` e
`⇧↓` tratam o cursor como “antes do início” e vão à primeira linha
visível / primeira pasta (o leitor não foca nada sozinho ao abrir o diff).

O popover de seleção liga `.focused($isQuestionFocused)` ao campo, mas
**não** pede foco ao aparecer (sem `onAppear` nem `defaultFocus`). Se o
campo recebe foco automático do sistema ou não, **não foi verificado**
só lendo o código; o que o código garante é o `onSubmit` quando o campo
está focado.

---

## Leitor de diff

Superfície: coluna central (`DiffViewer`), com o `ScrollView` focado.

### Modelo do cursor: uma linha da árvore

O cursor de teclado **não** é “um arquivo”. É **uma linha da árvore** —
arquivo **ou** pasta — na ordem em que a sidebar desenha, de cima para
baixo (`DiffTreeVisibleLines`).

**Visível** é a palavra-chave: descendentes de pasta **colapsada** não
entram na sequência. Fechar a pasta é o gesto de “terminei com isso”;
`→` / `←` / `⇧↑` / `⇧↓` **respeitam** e pulam o que está escondido.
Navegar com essas teclas **nunca** reabre pasta automaticamente.

- Cursor numa **arquivo**: o leitor rola até ele (como antes).
- Cursor numa **pasta**: o leitor **não** se move. O conteúdo da pasta
  se alcança continuando a andar na árvore.

`focusedFilePath` guarda o path da linha (arquivo, ou pasta com `/` no
fim). A sidebar destaca a linha com `surfaceSelected` — arquivo e pasta.

### Navegação lateral (setas, sem modificador)

Segurar `→` / `←` **repete** (varre linhas). Cada repetição troca o alvo;
quando o alvo é arquivo, usa snap sem animação
(`DiffReaderFileScrollStyle.rapid`) para não empilhar rolagens. `n` e
`v` **não** repetem.

| Tecla | Faz | Atua quando | Não atua quando | Código |
| --- | --- | --- | --- | --- |
| `→` | Próxima linha **visível** da árvore (pasta ou arquivo; sem wrap no fim); aceita key-repeat; **não** abre pasta | Leitor focado; modificadores vazios | Filtro, composer, ou outro first responder; `⌘` / `⌥` / `⌃` + seta | `DiffViewer` → `DiffReaderKeyPressPipeline` → `goToNextFile`; `DiffTreeVisibleLines`; `DiffKeyboardNavigationResolver.nextLine`; `DiffModel+Keyboard` |
| `←` | Linha visível anterior (sem wrap no início); idem | Idem | Idem | Idem com `goToPreviousFile` / `previousLine` |
| `n` | Próximo **arquivo** não lido (ordem do leitor), com wrap; **pode** abrir pastas colapsadas para revelar o alvo; fica parado se todos já estão lidos | Leitor focado; **sem** key-repeat | Idem; fase `.repeat` ignorada | `goToNextUnreadFile` + `ensureAncestorDirectoriesOpen` |
| `v` | Arquivo: alterna “viewed”. Pasta: marca/desmarca **todos** os descendentes e **fecha**/reabre a pasta (visto → fecha; desmarcar → abre) | Leitor focado; **sem** key-repeat | Idem; sem cursor: modelo no-op, tecla já consumida como `.handled` | `toggleViewedOnFocusedFile` |

### Pastas (Shift + setas)

Repetição de tecla **não** dispara nestes atalhos. `⇧` sozinho é
permitido no pipeline (um `modifiers.isEmpty` no viewer descartaria o
acorde).

| Tecla | Faz | Atua quando | Não atua quando | Código |
| --- | --- | --- | --- | --- |
| `⇧↓` | Próxima **pasta** na ordem visível; cursor **na linha da pasta**; leitor não rola; não abre pasta | Leitor focado; só Shift | Sem próximo pasta (fica parado) | `goToNextFolder` |
| `⇧↑` | Pasta anterior; cursor na linha da pasta | Idem | Sem pasta anterior | `goToPreviousFolder` |
| `⇧→` | Abre a pasta sob o cursor; se o cursor está num arquivo, abre a pasta-mãe | Leitor focado; só Shift; há pasta sob/acima do cursor | Raiz (arquivo sem pasta); pasta já aberta (no-op) | `openFocusedFolder` |
| `⇧←` | Fecha a pasta sob o cursor (ou a pasta-mãe do arquivo); se o cursor ficaria escondido, move o cursor para a linha da pasta | Idem | Raiz; pasta já fechada (no-op) | `closeFocusedFolder` |

`j` e `k` **não** fazem nada no leitor. Letras com modificador
(ex.: `⇧n`, `⌘v`) caem em `.ignored`.

As setas laterais **sem** Shift **não** passam por
`DiffReaderScrollKeyMapping` — são navegação de linha da árvore. Com
Shift, as quatro setas são acordes de pasta, nunca rolagem.

### Rolagem dentro do arquivo

Não é a rolagem nativa do sistema. `.focusable()` instala um
`KeyViewProxy` como first responder, então o AppKit **não** pagina o
`ScrollView` sozinho; o app aplica um salto discreto em
`scrollPosition.scrollTo(y:)` (`DiffViewer.swift`).

O passo de página é `0.9 ×` altura do viewport. Setas cima/baixo:

- toque único: `5 × DiffViewerMetric.codeLineHeight` (`arrowLineStepCount`)
- key-repeat (segurar): `3 ×` a mesma altura (`arrowLineRepeatStepCount`)

(`DiffReaderKeyboardScroll.swift`; `DiffViewer.swift`).

| Tecla | Faz | Atua quando | Não atua / observação | Código |
| --- | --- | --- | --- | --- |
| `Space` | Página para baixo | Leitor focado; só Shift como modificador opcional | `⌘` / `⌥` / `⌃` + Space: mapeamento rejeita | `DiffViewer.swift`; `DiffReaderKeyboardScroll.swift` |
| `⇧Space` | Página para cima | Leitor focado | Idem | Idem |
| `Page Down` | Página para baixo | Leitor focado, sem Shift | Com Shift o mapeamento devolve `nil` (não pagina) | Idem |
| `Page Up` | Página para cima | Leitor focado, sem Shift | Com Shift: idem, `nil` | Idem |
| `↓` | Cinco linhas para baixo no toque; três por repetição ao segurar | Leitor focado, sem Shift | Com Shift: navegação de pasta (`⇧↓`), não rolagem | Idem |
| `↑` | Cinco linhas para cima no toque; três por repetição ao segurar | Leitor focado, sem Shift | Com Shift: navegação de pasta (`⇧↑`), não rolagem | Idem |

Não há inércia, rubber-banding de trackpad, nem animação nesse caminho —
é um offset novo calculado e aplicado. `Home` / `End` não entram no
`switch` do mapeamento de rolagem; o handler devolve `.ignored` para
elas. O que o sistema faz depois disso **não foi verificado** no código.

---

## Sidebar (mapa de mudanças)

### Filtro

O `TextField` “Filter files…” tem `@FocusState` e anel de foco
(`DiffSidebar.swift`). **Não há** `onKeyPress`, `onSubmit` nem atalho
próprio: digitar filtra via binding; Enter não tem ação especial no
código.

Enquanto o filtro está focado, os atalhos do leitor **não** rodam.

### Árvore

Clique num arquivo chama `revealFileInReader` e devolve o foco ao leitor
(`DiffSidebarFileRow.swift`). **Não há** tratamento de teclado próprio
na árvore — as setas do leitor movem o cursor de linha, e a sidebar
rola para manter essa linha visível.

---

## Chat

Superfície: `DiffChatPanel`, visível quando `model.isChatOpen`.

| Tecla | Faz | Atua quando | Não atua / observação | Código |
| --- | --- | --- | --- | --- |
| `Return` | Envia o rascunho do composer | Composer (`TextEditor`) focado e `isEnabled` (`model.canUseSampleAgent`) | Se o composer está desabilitado, `Return` é **consumido** (`.handled`) sem enviar — nada visível acontece | `DiffChatPanel.swift` |
| `⇧Return` | Nova linha no rascunho | Composer focado | O handler devolve `.ignored` para o `TextEditor` inserir a quebra | `DiffChatPanel.swift` |
| `Escape` (`onExitCommand`) | Fecha o chat (`closeChat`) | Registrado no painel inteiro | Se dispara com o `TextEditor` como first responder **não foi verificado** só pelo código | `DiffChatPanel.swift`; `DiffModel+Chat.swift` |

Não há atalho de teclado no código para **abrir** o chat; a abertura
passa por ações do modelo (envio, ask/explain da seleção, etc.).

Enquanto o composer está focado, `→` / `←` / `n` / `v` / `Space` do
leitor não disparam.

---

## Popover de seleção

Aparece sobre o hunk quando há seleção e há agente
(`DiffHunkBlock.swift`).

| Tecla | Faz | Atua quando | Código |
| --- | --- | --- | --- |
| `Return` (`onSubmit` do `TextField`) | Envia a pergunta da seleção (`askAboutSelection`) e limpa o campo | Campo “Ask something specific…” focado (e a linha habilitada por `canAskAboutSelection`) | `DiffSelectionPopover.swift` |

Não há `onKeyPress` no popover. Não há atalho de teclado no código para
“Explain selection” — só o botão.

---

## Welcome

O editor de goal é um `TextEditor` com `@FocusState` só para o anel de
foco (`WelcomeView.swift`). **Não há** `onKeyPress` / `onSubmit` /
atalho para “Open diff” a partir do teclado no editor.

Botões com `dsFocusable` (incluindo “Open diff”) podem ser ativados pelo
comportamento padrão de botão focado no macOS (`Space` / `Return` quando
o botão é o first responder). Isso é `dsFocusable` em `DSModifiers.swift`
+ uso em `WelcomeView.swift`; **não** é um `keyboardShortcut` registrado
pelo app.

---

## Top bar do diff

Toggle da sidebar, pill de branches (voltar) e toggle de tema usam
`dsFocusable` (`DiffTopBar.swift`). Sem `keyboardShortcut`. Mesma regra:
só respondem a tecla se o botão estiver focado (comportamento de botão),
não há atalho global.

---

## O que não existe (e frustra se você procura)

Confirmado no código:

1. **Não há barra de menu com atalhos do app.** `DitGiffApp` só declara
   `WindowGroup` + `.windowStyle(.hiddenTitleBar)`. Não há `.commands`,
   `CommandGroup`, nem nenhum `keyboardShortcut` / `KeyEquivalent` no
   alvo da app. O menu mínimo que o sistema possa mostrar sozinho **não
   foi inspecionado em runtime**.

2. **Rolagem por teclado no leitor é paginação discreta**, não a
   rolagem inercial nativa. Ver seção do leitor e o comentário em
   `DiffViewer.swift`.

3. **Não há** atalho global para abrir/fechar sidebar, abrir chat, voltar
   à Welcome, alternar tema, ou marcar hunk como lido — só o que as
   tabelas acima listam.

4. **Não há** monitor de `NSEvent` (`addLocalMonitor` /
   `addGlobalMonitor`) no app.

---

## Observações (conflitos / tecla consumida sem efeito)

- Com o leitor focado, `→` na última linha visível, `←` na primeira,
  `n` com tudo lido, `⇧↓` / `⇧↑` sem pasta vizinha, `⇧→` / `⇧←` em
  no-op (raiz / já aberta / já fechada) e `v` sem cursor ainda retornam
  `.handled` no `onKeyPress` — a tecla é engolida mesmo quando o modelo
  não move nada.
- No composer desabilitado, `Return` é `.handled` sem enviar.
- `⇧Page Down` / `⇧Page Up` no leitor: o mapeamento devolve `nil` e o
  handler devolve `.ignored` — não paginam. `⇧↓` / `⇧↑` / `⇧←` / `⇧→`
  são atalhos de pasta, não rolagem.
- Foco num botão `dsFocusable` da top bar (via Tab, por exemplo) tira o
  leitor do caminho dos atalhos; `Space` nesse estado tenderia a ativar
  o botão, não a paginar o diff. Interação exata Tab ↔ leitor **não foi
  verificada** em runtime.
