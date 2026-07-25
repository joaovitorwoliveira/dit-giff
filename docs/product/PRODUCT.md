# git-diff-native (nome provisório)

Documento de produto. Resumo das decisões, não do raciocínio. O registro cru
da conversa que originou tudo isto vive no `NEXT-PRODUCT.md` do repositório
Mellon e é temporário.

Nome ainda não definido. `git-diff-native` é placeholder, será trocado.

## O que é

Um app nativo de macOS que transforma o diff de um merge request em um review
que você consegue defender. Você escolhe a branch e a branch-base, ele monta o
diff localmente, e usa IA pra explicar cada trecho, apontar o que parece
incidental ou mexido por engano, e listar as decisões que um revisor perguntaria
"por quê".

Uma frase: o preview de MR que devia existir localmente e não existe.

## Por que existe (a decisão de categoria)

Vem do aprendizado de um produto anterior (Mellon), que era um destino: pedia pro
usuário sair de onde trabalha. Não pegou, nem com o próprio autor, que era o
usuário-alvo.

A regra que saiu disso: não construa nada que exija mudar de onde o usuário
trabalha. Construa uma camada que envolve o fluxo atual e agrega valor sem pedir
migração. Referências: Maestri (canvas de terminais de agente) e Wispr Flow
(ditado). Superfície mínima, nenhuma migração, conectada a algo de alta
frequência.

## O problema que ataca

No fluxo com agentes, implementar virou barato: uma feature de uma semana sai em
~3h. O gargalo que sobrou é a revisão: ler o código que o agente escreveu pra
poder subir o MR com confiança. Num caso real, 95% pronto em 2h e 4 dias pra
abrir o MR, travado no medo de o revisor perguntar "por que essa decisão?" e não
saber responder.

O valor da revisão é humano e não pode ser terceirizado pra outro agente. Você
precisa entender o que entrega, e ler o código do agente é como você aprende. Por
isso o produto não revisa por você. Ele te faz ler e entender mais rápido, e te
deixa pronto pra defender cada decisão.

## Pilares de valor

1. UI de review melhor que o GitLab, com ou sem IA. Organiza a mudança, colapsa
   e minimiza o ruído, deixa navegar o macro sem dor.
2. IA que trabalha a partir do diff, sem exigir nada além dele. Explica um trecho
   sob demanda, sinaliza o que parece incidental / fora de escopo / mexido por
   engano, e levanta as decisões que um revisor questionaria.
3. Referência opcional. Uma spec, um ticket, ou uma frase de intenção, quando
   fornecida, deixa a resposta mais precisa. Nunca obrigatória.

## Princípios de conexão (zero fricção)

- Local. Lê o git da máquina. A dor mora no diff, e o diff mora no git, não no
  site. GitLab e GitHub saem de graça porque a fonte é o git.
- Usa as credenciais que a máquina já tem (chaves SSH, config de git). Zero
  configuração de repositório.
- Somente leitura. A IA não escreve código. Sem permissão de escrita no repo.
- Traz a própria IA. Usa a assinatura que o usuário já tem, chamando o Claude
  Code em modo headless. Sem API key nova pra gerenciar.

## O que está decidido

- Stack: Swift / macOS nativo. É um produto pessoal, pra uso desde o dia um, e uma
  escolha deliberada de craft e aprendizado.
- Read-only e BYO-IA via Claude Code headless. Provado por spike.
- Escopo é uma frase. Faz uma coisa: transforma branch-contra-base em review
  defensável. "Abrir qualquer repo, navegar qualquer código" fica de fora.

## Prova (spike, 23/07/2026)

Rodado num MR real (64 arquivos, +3242/-347):
`git diff base...branch | claude -p "<prompt>"`, headless, só leitura, 42s,
usando a assinatura já logada na máquina. Resultado: mapa da mudança, lista de
trechos suspeitos, e as decisões a defender. As duas capturas mais fortes (uma
mudança semântica sutil num check de cobrança, e uma função que passou a lançar
exceção) foram conferidas contra o diff e são reais. Conclusão: o mecanismo
funciona e o valor é real.

Piso testado foi só o diff. O teto é dar ao agente o contexto do projeto inteiro,
o que resolveria os pontos que o próprio modelo marcou como cegos.

## Em aberto

- Como o app apresenta os achados: como pistas, nunca como veredito, pra manter o
  humano no loop. É o que preserva o aprendizado.
- De onde vem o one-liner de intenção: digitado pelo usuário, ou inferido do nome
  da branch / commits / título do MR.
- Design da UI melhor que o GitLab.
- Nível de contexto dado à IA: só o diff (piso) vs. acesso de leitura ao projeto
  (teto).

## Anti-objetivos

- Não é workspace, nem árvore de arquivos, nem lugar onde algo precisa morar.
- A IA não escreve código nem sobe MR por você.
- Nada que exija o usuário trabalhar spec-first pra ter valor.
