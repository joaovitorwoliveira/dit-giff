# Roadmap até a v1

**A v1 é o dia em que eu largo o GitLab para ler meu próprio MR.** Abro um repositório
local, vejo minhas branches, escolho branch contra base, leio o diff inteiro dentro do
app, e pergunto para a IA usando a assinatura que já está logada na máquina.

Cada slice abaixo é um bloco grande de trabalho, para ser detalhado só na hora de pegar.
A ordem importa: cada um destrava o seguinte.

---

## Slice 6 — Syntax highlighting

Código sem cor cansa. Fica separado porque é grande e independente.

- Colorir por linguagem, com a paleta de syntax que já está no design system. Os valores
  do modo claro já são Solarized; os do escuro continuam vindo do protótipo v2. Nenhum dos
  dois está ligado a uma view ainda — hoje o diff pinta tudo com `textPrimary`.
- As linguagens que eu uso, não todas.
- Custo controlado: destacar só o que está na tela. A virtualização do Slice 3 já garante
  que só o viewport é materializado; o highlighting precisa respeitar isso.

**Pronto quando** o diff parece um editor, não um `cat`.

## Slice 7 — Contexto e prompt (mínimo que prova a tese)

Onde o produto se decide. Não é o chat completo — é o suficiente para eu ver se
"pistas, nunca veredito" funciona de verdade.

- O objetivo em uma frase e o `.md` de spec entrando no prompt.
- Pistas, nunca veredito. É regra de produto, e mora no prompt.
- Achados ancorados em arquivo e linha, para eu conferir.
- **Quando vale o agente sair do patch e explorar o repositório.** O Slice 4 travou isso
  para valer o tempo de espera: exploração livre custou dois minutos no primeiro uso real,
  lendo arquivos que nem estavam no diff. Mas às vezes é o arquivo vizinho que produz a
  pista boa. Distinguir os dois casos é trabalho de prompt.

**Decisão:** o diff inteiro nunca vai colado no prompt — não cabe no orçamento de forma
confiável. Vai o patch do arquivo que eu mandei explicar, junto com as ferramentas de git
read-only. Colar o patch também elimina o modo de falha em que o agente monta
`base..branch` no lugar de `base...branch`: os dois rodam, nenhum dá erro, e mostram
diffs diferentes.

**Decisão:** achado cujo arquivo ou linha não existe no patch real é **descartado**.
Uma pista que aponta para linha inexistente destrói a confiança em todas as outras.
O `Patch` do Slice 3 é a fonte de verdade contra a qual conferir.

**Decisão:** conteúdo vindo do repositório (o `.md` de spec, um `CLAUDE.md`) é entrada
**não confiável** quando o prompt o consome — um MR de fork pode plantar instruções
ali. Tratar como dado, nunca como instrução.

**Pronto quando** a resposta me faz ler melhor, em vez de ler por mim.

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

## Dívida conhecida

Nada aqui bloqueia a v1. São coisas que eu decidi não consertar na hora, com o motivo
registrado para eu não redescobrir o mesmo raciocínio daqui a três meses.

- **O flake do `SystemCommandRunnerTests`.** `manyCancelledRunsDoNotExhaustResources`
  falha por timeout no arquivo de pid de forma intermitente: falhou numa execução e
  passou na seguinte sem nenhuma mudança no código. Mora na camada de processo, que é a
  costura da qual o app inteiro depende, então é o flake que menos dá para ignorar para
  sempre.

- **A rolagem por teclado não tem a inércia do sistema.** Espaço e setas paginam de forma
  discreta. O caminho nativo está fechado: o `.focusable` do SwiftUI instala um proxy que
  engole o first responder, então a tecla nunca chega ao `NSScrollView`. Isso foi
  verificado com sonda, não deduzido. Só AppKit resolveria, e o `AGENTS.md` manda medir
  antes de reabrir essa migração.

- **Colapsar o corpo dos arquivos de uma pasta sem marcá-la como vista.**
  `toggleCollapsed(in:)` existe no model e nenhuma view chama. Fechar a pasta na árvore já
  não marca nada como visto; o que falta é só a versão que colapsa os corpos no leitor, e
  não está claro que alguém queira isso.

- **Uma escrita em disco por tecla apertada.** O progresso salva a cada mutação, sem
  debounce, e isso passou a incluir mudar o foco. Foi decisão consciente: debounce
  introduz uma costura de tempo que não dá para testar de forma determinística, e perde
  progresso se o app morrer. Nunca foi medido com a tecla segurada em autorepeat.

- **A barra de progresso não conta binário, submódulo nem arquivo vazio.** Ela conta hunks
  lidos, e esses três têm zero hunks. Marcar como visto funciona e a árvore esmaece; só o
  número não se mexe.

- **O que a impressão digital de um arquivo não-textual não alcança.** Ela é o cabeçalho
  cru que o git emitiu, então o oid de blob cobre mudança de conteúdo de binário. Se o git
  omitir a linha `index` de um binário que mudou, o cabeçalho não muda e o arquivo
  restaura como visto. Colisão de oid abreviado é teórica. Preferi a limitação registrada
  a uma solução que finge.

- **Arquivo de texto não confere o cabeçalho.** A impressão digital dele é só o corpo dos
  hunks. Não consegui construir um furo prático: chmod junto com edição já muda os hunks,
  e chmod sozinho cai no caminho de `noContent`, que usa o cabeçalho. Fica registrado como
  assimetria entre os dois caminhos, para quem mexer nisso depois.

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
  de exemplo, e o leitor virou utilizável num MR grande: sidebar redimensionável,
  controles de pasta na árvore, esmaecimento do que já foi visto e navegação por clique.
- **Slice 4 — A costura com a IA.** Explicar um arquivo funciona, streamando, com a
  assinatura já logada na máquina. Sem API key e sem passo de configuração.
- **Paleta e navegação.** O modo claro passou a derivar do Solarized Light, com os acentos
  do produto (`textError`, `diffAdd`, `diffDel`) preservados. Clicar num arquivo na árvore
  agora acerta o alvo: o pulo virou uma sequência de uma passada animada e duas corretivas
  depois que o layout assenta.
- **Organização do código.** `Features/Diff` saiu de 12 arquivos soltos para `Domain/`,
  `Model/` e `Views/`, sem nenhum arquivo acima de 500 linhas, e os testes passaram a
  espelhar a estrutura do app. O padrão está no `AGENTS.md`.
- **Slice 5 — O leitor por teclado, e o progresso que sobrevive.** `j` e `k` andam entre
  arquivos, `n` vai para o próximo não lido e `v` marca como visto; espaço e as setas rolam
  dentro do arquivo. Binário, submódulo e arquivo sem conteúdo passaram a existir no leitor
  como uma entrada curta, em vez de aparecer só na árvore. E onde eu parei sobrevive a
  fechar o app, por par de repositório e branch, conferindo arquivo por arquivo: só mantém
  o progresso de quem tem o patch idêntico ao da última vez.

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
