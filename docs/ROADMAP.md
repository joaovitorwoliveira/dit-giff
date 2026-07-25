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
acabamento continua por último.

**Correção de rota feita durante o Slice 3.** Parte do Slice 6 foi puxada para a frente,
contra esta ordem, por um motivo específico: com o diff real na tela, um MR de 169
arquivos travava o app e a sidebar tinha largura fixa. Não era refinamento adiável — era
a ferramenta não servindo na primeira tentativa de uso. Ler o próprio MR ficou possível
antes de a IA existir, então valia consertar. O que sobrou do Slice 6 continua depois da
IA.

---

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

**Onde encaixar:** o leitor já tem o lugar da IA construído e desligado. `DiffCannedAgent`
é a única fonte de texto de agente e vale `nil` em sessão real, o que desabilita explicar,
o popover de seleção e o chat. O Slice 4 **introduz uma fonte real** no lugar desse `nil`;
não há `if` espalhado para lembrar de trocar.

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
O `Patch` do Slice 3 é a fonte de verdade contra a qual conferir.

**Decisão:** conteúdo vindo do repositório (o `.md` de spec, um `CLAUDE.md`) é entrada
**não confiável** quando o prompt o consome — um MR de fork pode plantar instruções
ali. Tratar como dado, nunca como instrução.

**Pronto quando** a resposta me faz ler melhor, em vez de ler por mim.

## Slice 6 — O leitor (o que sobrou)

Marcar como lido, colapsar, esmaecer, a árvore, a sidebar redimensionável, navegar
clicando no arquivo e a rolagem fluida foram feitos junto com o Slice 3. O que falta:

- Navegação por teclado, e ir para o próximo não lido.
- Onde eu parei sobrevive a fechar o app, por par de repositório e branch.
- Colapsar uma pasta **sem** marcá-la como vista. Hoje as duas ações andam juntas, de
  propósito; se na prática fizer falta separar, é aqui.
- Arquivo binário, submódulo e arquivo sem conteúdo aparecem na árvore mas não existem
  no leitor. Deveriam aparecer como uma entrada curta dizendo o que são, para que clicar
  neles funcione como em qualquer outro arquivo.

**Pronto quando** eu leio um MR inteiro sem tocar no mouse.

## Slice 7 — Syntax highlighting

Código sem cor cansa. Fica separado porque é grande e independente.

- Colorir por linguagem, com a paleta `sx-*` que já está no design system.
- As linguagens que eu uso, não todas.
- Custo controlado: destacar só o que está na tela. A virtualização do Slice 3 já garante
  que só o viewport é materializado; o highlighting precisa respeitar isso.

**Pronto quando** o diff parece um editor, não um `cat`.

## Slice 8 — O chat por diff

- Explicar um arquivo pelo botão do cabeçalho.
- Selecionar linhas, popover, explicar ou perguntar; o trecho vira chip na mensagem.
- Uma thread por diff, que morre quando eu troco de branch.
- Indicador de pensamento enquanto gera.

A casca inteira já existe e está desligada em sessão real. Ligar é trocar a fonte de
resposta, não construir a tela.

**Pronto quando** eu discuto um trecho sem sair da leitura.

## Slice 9 — Acabamento

O que separa "funciona na minha máquina" de "eu uso todo dia".

- Tema claro conferido de ponta a ponta, janela e estado restaurados.
- Atalhos de teclado, estados vazios e de erro em todas as telas.
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
- **Slice 3 — Git real: ler e entender o diff.** O diff de verdade substituiu os dados
  de exemplo, e o leitor virou utilizável num MR grande.

### O que o Slice 3 decidiu, e não vale reabrir

- **Dois comandos git, casados por caminho.** O patch unificado dá o corpo; um
  `git diff --raw -z` dá status, renomeação e modo de forma autoritativa. Ler o status a
  partir do cabeçalho `diff --git a/… b/…` é ambíguo com nome de arquivo que tem espaço.
  O casamento é por caminho de destino, nunca por posição, e caminho órfão de qualquer
  lado **falha alto**. Mostrar o status de um arquivo no diff de outro, em silêncio, é o
  pior defeito possível num produto que vive de confiança.
- **Formato forçado por `-c`.** `core.quotePath=false`, `diff.noprefix=false`,
  `mnemonicPrefix=false`, prefixos explícitos. A config global do usuário pode quebrar o
  parsing, e o bug só apareceria na máquina de quem tem aquela config.
- **Tipo limpo + adaptador.** O parser produz um `Patch` que só contém a verdade do git;
  uma camada fina converte no que a tela desenha. Os campos de IA não contaminam o tipo
  que representa o que o git disse.
- **O retorno de carro é conteúdo, não separador.** O git separa as linhas do patch com
  LF sozinho. Limpar o `\r` esconderia um commit que só converte CRLF para LF — que é
  exatamente a mudança invisível que um leitor de diff precisa mostrar. Confirmado nos
  bytes, não no papel.
- **Sessão real nunca vê texto de IA inventado.** `DiffCannedAgent` é a única fonte de
  resposta enlatada e vale `nil` ao vivo; explicar, popover e chat ficam desabilitados
  até o Slice 4. É estrutural, não uma flag: o Slice 4 precisa *introduzir* uma fonte,
  não lembrar de checar um `if`. Um teste exercita todas as portas de entrada.
- **SwiftUI deu conta da rolagem. AppKit não foi preciso.** A previsão antiga era que um
  diff grande exigiria `NSTableView`. O travamento não era volume: a virtualização
  existia só no nível do arquivo, e cada arquivo materializado desenhava todos os hunks e
  todas as linhas, com um `ScrollView` horizontal por hunk. Com virtualização até a
  linha, um `Text` por linha e um único `ScrollView`, 900 arquivos rolam liso. **Não
  reabra a migração para AppKit sem medir primeiro.**
- **Linha longa quebra; não há rolagem horizontal.** A rolagem horizontal exigia
  `ScrollView` bidirecional, e um `ScrollView` que rola num eixo propõe largura ilimitada
  ao conteúdo — o que faz `maxWidth: .infinity` deixar de significar "ocupe a tela".
  Três bugs de layout seguidos saíram daí. Quebrar a linha eliminou a causa e removeu
  código.

### Puxado do Slice 6 junto com o Slice 3

- Sidebar redimensionável por arrasto, com largura persistida. Durante o gesto só uma
  linha guia se move; o layout é aplicado uma vez ao soltar, porque redimensionar a cada
  pixel invalidava todo o conteúdo materializado e travava o app.
- Controles de pasta na árvore: marcar todos os descendentes como vistos, com estado de
  três valores (nenhum, alguns, todos) e invalidação de cache uma vez por lote.
- Arquivo e pasta vistos aparecem esmaecidos na árvore.
- Clicar num arquivo na árvore leva o leitor até ele, ancorado no topo. Ancorar no topo e
  não no centro é deliberado: centralizado joga o cabeçalho do arquivo acima da dobra.
  Arquivo colapsado não é expandido ao navegar — navegar e expandir são gestos
  diferentes.
