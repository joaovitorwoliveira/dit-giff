# Roadmap até a v1

**A v1 é o dia em que eu largo o GitLab para ler meu próprio MR.** Abro um repositório
local, vejo minhas branches, escolho branch contra base, leio o diff inteiro dentro do
app, e pergunto para a IA usando a assinatura que já está logada na máquina.

Cada slice abaixo é um bloco grande de trabalho, para ser detalhado só na hora de pegar.
A ordem importa: cada um destrava o seguinte.

---

## Slice 2 — Git real: repositório e branches

A Welcome para de mentir. Primeiro contato do app com o disco.

- Abrir pasta pelo seletor nativo e por arrastar; validar que é repositório.
- Listar branches locais e remotas, descobrir a base provável, contar a divergência.
- Repositórios recentes que sobrevivem ao fechar o app.
- Erros com nome: não é repo, sem commits, branch sumiu, repo movido.

**Pronto quando** eu abro o dit-giff de verdade e vejo minhas branches reais.

## Slice 3 — Git real: ler e entender o diff

O maior bloco de engenharia do projeto. Transformar texto do git em algo que a tela
sabe desenhar.

- Rodar `git diff base...branch` pela costura que já existe.
- Parsing: arquivos, status, renomeações, hunks, linhas, e a diferença dentro da linha.
- Binários, arquivos gigantes, submódulos, permissões, encoding.
- Fixtures de repositórios reais, porque parsing provado contra string escrita à mão
  não vale nada.

**Pronto quando** um MR de 64 arquivos abre e está correto contra o `git diff` no
terminal.

## Slice 4 — O leitor

O que faz disso uma ferramenta de leitura longa e não um visualizador.

- Marcar arquivo como lido, colapsar, esmaecer; o mesmo estado na sidebar.
- Filtro da árvore, navegação por teclado, ir para o próximo não lido.
- Onde eu parei sobrevive a fechar o app, por par de repositório e branch.
- Rolagem fluida num diff grande — provavelmente onde o SwiftUI puro não chega e o
  AppKit entra.

**Pronto quando** eu leio um MR inteiro sem perder o lugar.

## Slice 5 — Syntax highlighting

Código sem cor cansa. Fica separado porque é grande e independente.

- Colorir por linguagem, com a paleta `sx-*` que já está no design system.
- As linguagens que eu uso, não todas.
- Custo controlado: destacar só o que está na tela.

**Pronto quando** o diff parece um editor, não um `cat`.

## Slice 6 — A costura com a IA

O que o spike já provou, virando produto. A costura de processos foi construída para
este momento.

- Chamar `claude -p` headless com a assinatura da máquina; sem API key.
- Resposta em streaming, cancelável, com escolha de modelo e esforço.
- Falhar com clareza: `claude` não instalado, não logado, sem rede, tempo esgotado.
- Um segundo adapter atrás do mesmo protocolo, se o Claude Code não der conta —
  cursor CLI ou codex entram sem tocar no resto do app.

**Pronto quando** eu peço uma explicação e ela chega, sem ter configurado nada.

## Slice 7 — O chat por diff

- Explicar um arquivo pelo botão do cabeçalho.
- Selecionar linhas, popover, explicar ou perguntar; o trecho vira chip na mensagem.
- Uma thread por diff, que morre quando eu troco de branch.
- Indicador de pensamento enquanto gera.

**Pronto quando** eu discuto um trecho sem sair da leitura.

## Slice 8 — Contexto e prompt

Onde o produto se decide. Está listado como "em aberto" no `PRODUCT.md` e é o que
separa uma resposta útil de uma genérica.

- O que vai para o modelo: só o diff, ou leitura do projeto inteiro.
- O objetivo em uma frase e o `.md` de spec entrando no prompt.
- Pistas, nunca veredito. É regra de produto, e mora no prompt.
- Achados ancorados em arquivo e linha, para eu conferir.

**Pronto quando** a resposta me faz ler melhor, em vez de ler por mim.

## Slice 9 — Acabamento

O que separa "funciona na minha máquina" de "eu uso todo dia".

- Tema claro conferido de ponta a ponta, janela e estado restaurados.
- Atalhos de teclado, estados vazios e de erro em todas as telas.
- Desempenho num diff grande de verdade.
- Ícone, primeira execução, e o app abrindo fora do Xcode.

**Pronto quando** eu abro pelo Launchpad e não penso no Xcode.

---

## Feito

- **Fundação.** Design system em Swift (cor, espaço, tipo, motion, JetBrains Mono), a
  costura de processos com fake e adapter, e a tela Welcome como protótipo estático.
- **Slice 1 — A tela de diff, estática.** Barra, sidebar com árvore e filtro, leitor com
  hunks e destaque de palavra, popover e chat em casca, tudo com dados de exemplo.
