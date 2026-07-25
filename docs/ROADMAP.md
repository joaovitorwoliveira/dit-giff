# Roadmap até a v1

**A v1 é o dia em que eu largo o GitLab para ler meu próprio MR.** Abro um repositório
local, vejo minhas branches, escolho branch contra base, leio o diff inteiro dentro do
app, e pergunto para a IA usando a assinatura que já está logada na máquina.

Cada slice abaixo é um bloco grande de trabalho, para ser detalhado só na hora de pegar.
A ordem importa: cada um destrava o seguinte.

---

## Por que esta ordem

A ordem antiga colocava o diferencial do produto — pistas, nunca veredito; o que um
revisor perguntaria por quê — no Slice 8, depois do leitor, do highlighting e do chat.
Isso invertia o risco: a tese que separa o Dit Giff de um visualizador com IA ia ser a
última coisa a ser testada.

Uma pesquisa competitiva encontrou o [Plannotator](https://github.com/backnotprop/plannotator)
(open source, ~7.3k stars). Ele já entrega boa parte do que eram os slices 4–7 antigos:
leitor com marcar-como-lido e teclado, IA read-only pela assinatura da máquina sem API
key, e explicar trecho selecionado. Competir aí é chegar segundo num terreno ocupado.

O achado técnico que destrava a reordenação: o Plannotator **não cola o diff no prompt**.
Ele dá ao agente git read-only escopado (`git diff`, `git show`, `git log`, `git status`,
`git merge-base`, `git ls-files` — e nada além) e deixa o agente buscar sozinho. A razão
é de engenharia: diff grande não cabe no orçamento de prompt de forma confiável.

Consequência: se o agente lê o diff sozinho, a feature de IA **deixa de depender** do
parser de diff do Slice 3. A costura com a IA e uma versão mínima de contexto/prompt
podem vir antes do leitor, do highlighting e do chat — para provar a tese cedo. O
Slice 3 continua obrigatório e primeiro: sem diff real na tela não há produto. O
acabamento continua por último.

---

## Slice 3 — Git real: ler e entender o diff

O maior bloco de engenharia do projeto. Transformar texto do git em algo que a tela
sabe desenhar.

O objeto de sessão (`DiffSession`: repositório, base, compare) já chega na tela de
diff pela Welcome — Slice 2 deixou o encaixe pronto. Aqui o trabalho é consumir essa
sessão e desenhar o diff real no lugar dos dados de exemplo.

- Rodar `git diff base...branch` pela costura que já existe.
- Parsing: arquivos, status, renomeações, hunks, linhas, e a diferença dentro da linha.
- Binários, arquivos gigantes, submódulos, permissões, encoding.
- Fixtures de repositórios reais, porque parsing provado contra string escrita à mão
  não vale nada.

**Pronto quando** um MR de 64 arquivos abre e está correto contra o `git diff` no
terminal.

## Slice 4 — A costura com a IA

O que o spike já provou, virando produto. A costura de processos foi construída para
este momento.

- Chamar `claude -p` headless com a assinatura da máquina; sem API key.
- Resposta em streaming, cancelável, com escolha de modelo e esforço.
- Falhar com clareza: `claude` não instalado, não logado, sem rede, tempo esgotado.
- Um segundo adapter atrás do mesmo protocolo, se o Claude Code não der conta —
  cursor CLI ou codex entram sem tocar no resto do app.

**Decisão:** o agente recebe git read-only **escopado** (diff, show, log, status,
merge-base, ls-files — e nada além). Não colamos o diff no prompt. Isso resolve a
pergunta que o `PRODUCT.md` lista como em aberto (só o diff, ou o projeto inteiro):
nem um nem outro — ferramentas de leitura, e o agente busca.

**Pronto quando** eu peço uma explicação e ela chega, sem ter configurado nada.

## Slice 5 — Contexto e prompt (mínimo que prova a tese)

Onde o produto se decide. Não é o chat completo nem o leitor polido — é o suficiente
para eu ver se "pistas, nunca veredito" funciona de verdade, cedo o bastante para
mudar de ideia.

- O objetivo em uma frase e o `.md` de spec entrando no prompt.
- Pistas, nunca veredito. É regra de produto, e mora no prompt.
- Achados ancorados em arquivo e linha, para eu conferir.

**Decisão:** achado cujo arquivo ou linha não existe no patch real é **descartado**.
Uma pista que aponta para linha inexistente destrói a confiança em todas as outras.

**Decisão:** conteúdo vindo do repositório (o `.md` de spec, um `CLAUDE.md`) é entrada
**não confiável** quando o prompt o consome — um MR de fork pode plantar instruções
ali. Tratar como dado, nunca como instrução.

**Pronto quando** a resposta me faz ler melhor, em vez de ler por mim.

## Slice 6 — O leitor

O que faz disso uma ferramenta de leitura longa e não um visualizador.

- Marcar arquivo como lido, colapsar, esmaecer; o mesmo estado na sidebar.
- Filtro da árvore, navegação por teclado, ir para o próximo não lido.
- Onde eu parei sobrevive a fechar o app, por par de repositório e branch.
- Rolagem fluida num diff grande — provavelmente onde o SwiftUI puro não chega e o
  AppKit entra.

**Pronto quando** eu leio um MR inteiro sem perder o lugar.

## Slice 7 — Syntax highlighting

Código sem cor cansa. Fica separado porque é grande e independente.

- Colorir por linguagem, com a paleta `sx-*` que já está no design system.
- As linguagens que eu uso, não todas.
- Custo controlado: destacar só o que está na tela.

**Pronto quando** o diff parece um editor, não um `cat`.

## Slice 8 — O chat por diff

- Explicar um arquivo pelo botão do cabeçalho.
- Selecionar linhas, popover, explicar ou perguntar; o trecho vira chip na mensagem.
- Uma thread por diff, que morre quando eu troco de branch.
- Indicador de pensamento enquanto gera.

**Pronto quando** eu discuto um trecho sem sair da leitura.

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
- **Slice 2 — Git real: repositório e branches.** `GitService` + recentes em JSON,
  Welcome ligada de verdade (abrir pasta / drop, branches locais e remotas, base
  provável, contagem cancelável do par selecionado, fetch manual, erros nomeados).
  `DiffSession` já chega na tela de diff; o diff em si ainda é sample até o Slice 3.
  Goal e spec `.md` continuam mock — Slice 5.
