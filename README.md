# Dit Giff

App nativo de macOS pra ler o diff inteiro entre uma branch e sua base *antes* de
abrir o merge request. Ferramenta de leitura longa: conforto acima de espetáculo.

Documento de produto: [`docs/product/PRODUCT.md`](docs/product/PRODUCT.md).

## Estrutura

```
DitGiff/              App SwiftUI. Abra DitGiff.xcodeproj daqui.
docs/product/         Especificacoes: produto, design system, setup Swift.
docs/design-handoff/  Prototipos HTML e spec do Claude Design (referencia).
ds-bundle/            Tokens do design system. GERADO — ver abaixo.
assets/icon/          Fonte do icone do app, desenhado por codigo.
.design-sync/         Configuracao do sync com o Claude Design.
```

## Pontos que não são óbvios

**`ds-bundle/` é gerado, não editado à mão.** O `.design-sync/config.json` aponta
`outDir` pra essa pasta: o próximo sync sobrescreve o que estiver lá. Mover ou
renomear quebra o sync. Pra mudar um token, edite
[`docs/product/DESIGN-SYSTEM.md`](docs/product/DESIGN-SYSTEM.md), que é a fonte
canônica, e rode o sync.

**`docs/design-handoff/` é uma referência congelada, não código.** Os `.dc.html`
são protótipos de design, e o `support.js` é o runtime do protótipo — nada ali é
pra copiar pro app. Servem pra ler layout, cor, tipografia, espaçamento e intenção
de interação exatos. O `DESIGN-SYSTEM-tokens/` dentro dessa pasta é uma cópia
do `ds-bundle/` no momento do handoff; para desenvolvimento, use o `ds-bundle/`.

**O ícone é desenhado por código.** Os PNGs em `assets/icon/` são artefatos de
build, gerados por `render-icon.swift` via `./build.sh`. Nunca edite os PNGs; edite
as constantes no topo do script. O `AppIcon.appiconset` já está copiado para o
asset catalog do app — ao regerar o ícone, copie de novo.

**O App Sandbox está desligado de propósito.** O app roda `git` e `claude` como
processos externos, o que o sandbox bloqueia. É um build setting
(`ENABLE_APP_SANDBOX = NO`), não um arquivo `.entitlements` — o Xcode 16+ mudou
isso de lugar. Religar o sandbox quebra o núcleo do produto.

## Rodar

Abra `DitGiff/DitGiff.xcodeproj` no Xcode e tecle `Cmd+R`. Requer Xcode instalado;
o passo a passo de quem nunca mexeu com Swift está em
[`docs/product/SWIFT-SETUP.md`](docs/product/SWIFT-SETUP.md).
