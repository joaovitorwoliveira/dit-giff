# Ícone do Dit Giff

O ícone é desenhado por código, não exportado de um gerador de imagem. O design é
inteiramente geométrico, então `render-icon.swift` produz o mesmo resultado, com o
mesmo hex e a mesma geometria, em toda execução. Para mudar qualquer coisa — cor,
espessura, distância entre os olhos — edite as constantes no topo do script e rode
`./build.sh`. Nunca edite os PNGs à mão: eles são artefatos de build.

## Arquivos

| Arquivo | Para quê |
| --- | --- |
| `render-icon.swift` | A fonte da verdade. Todo o desenho vive aqui. |
| `build.sh` | Renderiza e empacota tudo. |
| `AppIcon.appiconset/` | Arraste para dentro de `Assets.xcassets` no Xcode. |
| `DitGiff.icns` | Para um bundle montado fora do Xcode. |
| `DitGiff.iconset/` | Os dez PNGs crus. Entrada do `iconutil`. |
| `icon.svg` | Master vetorial: site, README, Icon Composer. |
| `icon-1024-fullbleed.png` | Squircle ocupando a tela inteira, sem margem nem sombra. |
| `icon-1024-macos-grid.png` | Grid clássico do macOS: corpo 824/1024 com sombra. |
| `symbol-monochrome.png` | Só os dois sinais, preto sobre transparente. |

## Paleta

| | Hex | |
| --- | --- | --- |
| Verde sálvia | `#8FBF8A` | o olho aberto — o `+` |
| Coral | `#F07A64` | o olho fechado — o `−` |
| Preto-verde | `#0D1712` | campo esquerdo |
| Preto-quente | `#1A100E` | campo direito |

## Tamanhos pequenos têm arte própria

De 16px a 64px o ícone não é o grande reduzido. A margem do grid e a sombra comem
quase todo o canvas e os traços caem abaixo de um pixel, então o corpo cresce, os
traços engrossam, os efeitos suaves somem e a geometria é encaixada na grade de
pixels. É a razão de um `.iconset` ter dez arquivos em vez de um. Os perfis por
tamanho estão em `SizeProfile.forSize`.

## macOS 26 e Icon Composer

Os arquivos acima são o caminho clássico e funcionam em qualquer versão do macOS. Se
o app for adotar o sistema de ícones novo do macOS 26, o Icon Composer espera camadas
separadas em vez de um PNG achatado, e desenha o squircle, o brilho da borda e a
sombra por conta própria. Nesse caso as camadas a fornecer seriam o fundo dividido e
os dois sinais, sem os efeitos — use o `icon.svg` como base. Confirme os requisitos
atuais na documentação da Apple antes de montar o `.icon`.
