# Começar em Swift (macOS nativo)

Guia mínimo pra sair do zero, escrito pra quem vem de JavaScript/web e nunca
mexeu com Swift. Só o básico pra conseguir começar. O planejamento de fato vem
depois.

## A primeira decisão: SwiftUI ou AppKit

macOS tem dois frameworks de UI nativos:

- SwiftUI (moderno, declarativo). A view é função do estado, com `@State`. Em
  espírito é muito parecido com React, então vindo de web você se sente em casa.
  Menos boilerplate. É o padrão recomendado hoje pra apps novos.
- AppKit (o "Apple Kit" que você mencionou). Mais poderoso e granular, mas
  verboso e imperativo. É a base histórica dos apps de Mac.

Recomendação: comece em SwiftUI. Quando precisar de algo que ele não expõe, dá
pra descer pro AppKit em pontos específicos (via `NSViewRepresentable`). Não
precisa escolher tudo agora.

## O que baixar

1. Xcode, na Mac App Store, gratuito. É o IDE e traz tudo: compilador Swift, SDK
   do macOS, editor visual. É grande, vários GB.
2. Só isso pra começar. As ferramentas de linha de comando vêm junto. Se quiser
   separadas: `xcode-select --install`.
3. Não precisa de conta paga da Apple pra desenvolver e rodar no teu próprio Mac.
   A conta de Developer (US$99/ano) só entra se um dia for distribuir, notarizar
   ou publicar na App Store.

## Criar o projeto

No Xcode: `File > New > Project > macOS > App`. Escolha:

- Interface: SwiftUI
- Language: Swift

Isso gera o esqueleto do app com uma janela e uma view inicial. Roda com Cmd+R e
já abre uma janela nativa.

## Dependências

O gerenciador é o Swift Package Manager (SPM), embutido no Xcode. É o "npm" do
Swift. Adiciona pacotes por `File > Add Package Dependencies` com a URL do
repositório.

## Os dois primitivos técnicos que ESTE produto precisa

1. Rodar processos, pra chamar `git` e o `claude` headless. Em Swift é a API
   `Process` (roda um binário e captura o stdout). É como o app vai fazer
   `git diff base...branch` e depois `claude -p`.
   - Atenção ao sandbox. Se você ligar o App Sandbox (obrigatório só pra App
     Store), rodar binários externos como `git` e `claude` é bloqueado. Pra um app
     pessoal fora da App Store, deixe o sandbox desligado e o `Process` roda
     livre. Vale decidir isso cedo.
2. Renderizar o diff, com cor de sintaxe e o verde/vermelho. Dá pra montar com
   `AttributedString` / `Text` do SwiftUI, ou usar um pacote de syntax highlight
   (ex.: Splash, Highlightr). Confirme qual está atual antes de adotar. É a parte
   mais trabalhosa da UI nativa; deixe pra depois do miolo funcionar.

## Primeiro marco sugerido (o "hello world" DESTE produto)

Antes de UI bonita, prove que consegue amarrar as pontas:

1. Uma janela com dois campos de texto (branch base e branch alvo) e um botão.
2. No clique, `Process` roda `git -C <repo> diff <base>...<alvo>` e joga o stdout
   cru num scroll view.
3. Depois, um segundo botão que manda esse diff pro `claude -p` e mostra a
   resposta.

Se chegar aqui, o spike virou app. Todo o resto (UI melhor que o GitLab, seleção
de trecho, apresentação dos achados) é refino em cima disso.

## Pra estudar

- Apple SwiftUI Tutorials, tutorial oficial em developer.apple.com/tutorials/swiftui
- 100 Days of SwiftUI (Paul Hudson, Hacking with Swift), gratuito e ótimo pra
  começar
- Swift.org, a linguagem e o guia oficial
- Documentação do `Process` e do `AttributedString` na Apple Developer
  Documentation

Se algum link mudou de lugar, procure pelo nome. São todos recursos oficiais ou
consolidados.
