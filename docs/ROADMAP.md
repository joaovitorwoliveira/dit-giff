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

**Refinado no Slice 4:** o diff inteiro continua nunca sendo colado, mas o patch do
arquivo que o usuário mandou explicar vai colado junto com as ferramentas. Corta a
latência pela metade e elimina o modo de falha em que o agente monta `base..branch` no
lugar de `base...branch` — os dois rodam, nenhum dá erro, e mostram diffs diferentes.

**Correção de rota feita durante o Slice 3.** Parte do Slice 6 foi puxada para a frente,
contra esta ordem, por um motivo específico: com o diff real na tela, um MR de 169
arquivos travava o app e a sidebar tinha largura fixa. Não era refinamento adiável — era
a ferramenta não servindo na primeira tentativa de uso. Ler o próprio MR ficou possível
antes de a IA existir, então valia consertar. O que sobrou do Slice 6 continua depois da
IA.

---

## Slice 5 — Contexto e prompt (mínimo que prova a tese)

Onde o produto se decide. Não é o chat completo nem o leitor polido — é o suficiente
para eu ver se "pistas, nunca veredito" funciona de verdade, cedo o bastante para
mudar de ideia.

- O objetivo em uma frase e o `.md` de spec entrando no prompt.
- Pistas, nunca veredito. É regra de produto, e mora no prompt.
- Achados ancorados em arquivo e linha, para eu conferir.
- **Quando vale o agente sair do patch e explorar o repositório.** O Slice 4 travou isso
  para valer o tempo de espera: exploração livre custou dois minutos no primeiro uso real,
  lendo arquivos que nem estavam no diff. Mas às vezes é o arquivo vizinho que produz a
  pista boa. Distinguir os dois casos é trabalho de prompt.

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

O Slice 4 já entregou explicar arquivo pelo cabeçalho, a thread que acumula e morre com
a branch, e o indicador de atividade. O que falta é conversar.

- Perguntar em texto livre pelo composer, que hoje fica visível com o envio desabilitado.
- Histórico de verdade: a pergunta seguinte lembra da anterior. A continuidade vem de
  processo vivo alimentado por stdin, **não** de retomar sessão do disco — o Slice 4
  decidiu não persistir sessão para não poluir o `claude -c` do usuário no próprio
  repositório dele.
- Selecionar linhas, popover, explicar ou perguntar; o trecho vira chip na mensagem.
- Avisar ao trocar de modelo no meio da thread. Hoje não faz sentido — cada explicação é
  uma chamada independente e não há contexto a perder. Com histórico, passa a ter.

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
  de exemplo, e o leitor virou utilizável num MR grande. Trouxe junto, do Slice 6, a
  sidebar redimensionável, os controles de pasta na árvore, o esmaecimento do que já foi
  visto e a navegação por clique.
- **Slice 4 — A costura com a IA.** Explicar um arquivo funciona, streamando, com a
  assinatura já logada na máquina. Sem API key e sem passo de configuração.

### O que não vale reabrir

Do Slice 3:

- **Dois comandos git, casados por caminho de destino.** O patch dá o corpo, o
  `--raw -z` dá status e renomeação. Caminho órfão de qualquer lado **falha alto** —
  mostrar o status de um arquivo no diff de outro, em silêncio, é o pior defeito
  possível num produto que vive de confiança.
- **Formato forçado por `-c`** (`core.quotePath`, `diff.noprefix`, `mnemonicPrefix`).
  A config global do usuário quebraria o parsing, e só na máquina de quem a tem.
- **Tipo limpo + adaptador.** O `Patch` só contém a verdade do git; uma camada fina
  converte no que a tela desenha.
- **O retorno de carro é conteúdo, não separador.** Limpar o `\r` esconderia um commit
  que só converte CRLF para LF — a mudança invisível que um leitor precisa mostrar.
- **SwiftUI deu conta da rolagem.** O travamento não era volume, era virtualização parada
  no nível do arquivo. **Não reabra a migração para AppKit sem medir primeiro.**
- **Linha longa quebra; não há rolagem horizontal.** Um `ScrollView` que rola num eixo
  propõe largura ilimitada, e `maxWidth: .infinity` deixa de significar "ocupe a tela".

Do Slice 4, tudo verificado empiricamente e não por documentação:

- **A trava de permissão é `--tools Bash` + `--permission-mode dontAsk` + os seis
  `--allowedTools` de git.** `--allowedTools` sozinha **não restringe nada** — auto-aprova
  o que lista e nega nada. `--permission-mode manual` é aceito e **silenciosamente
  ignorado**. `deny: ["Bash"]` mata o git junto. Lista de proibidos foi rejeitada por
  princípio: bloqueia só o que enumera.
- **`--safe-mode` em toda chamada.** Sem ele, o `CLAUDE.md`, os hooks e as settings do
  repositório aberto alcançam o agente — e a branch de um terceiro executaria código na
  máquina só por ser aberta para leitura.
- **`.finished` é a única prova de resposta completa**, e depende do evento `result` do
  CLI. Stream que acaba sem ele é falha, nunca prosa parcial deixada na tela.
- **Cada falha tem seu detector, nenhum lê stderr.** Binário ausente na localização;
  não logado por `claude auth status --json` antes de gastar chamada; sem rede no segundo
  `api_retry` (o CLI tenta dez vezes por 184s e nunca fica em silêncio); travado por 60s
  sem evento nenhum.
- **O protocolo do agente fala em produto, não em transporte.** Tudo que é Claude Code
  vive num adapter só, que é o que mantém a troca por outro CLI barata.
