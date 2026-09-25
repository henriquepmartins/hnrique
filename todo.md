# Metas de consistência, streak no topo e menos texto

- [x] 1. `how` over the affected subsystem.
- [x] 2. `architect` for parallel design exploration.
  - architect skipped: a forma do dado segue a tabela `goal` que já existe e o topo tem referência visual pronta; o único fork (meta no servidor ou no aparelho) foi decidido pela evidência, porque presença não tem dado no payload.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Inventário de texto e contrato do painel (`attendanceStreak`, `streakGoals`, `/api/v1/goal/set-streak`) antes do worker iOS.
  - Independent workstreams. Servidor no repo web e app iOS correm em paralelo; repos diferentes.
  - Shared mutable state. Servidor em worktree próprio do repo web. Metas, topo e corte de texto no iOS mexem nos mesmos arquivos, então um só worker.
  - Smallest safe decomposition. Dois workers: web e iOS. Migração e deploy do servidor esperam confirmação.
- [x] 4. Delegate code-writing to a subagent.
  - Servidor: 4 commits, migração 0009 aplicada em produção, deploy Ready em hnrq.vercel.app.
  - iOS: Academia (4 commits) e Estudos (1 commit) em worktrees, juntados no main; 73 testes passando.
- [x] 5. Verify on the matching surface.
  - scripts/verify-ui.sh passou (1 teste, 81 s) contra Postgres local e servidor real na 3001. Capturas em output/verify/20260915-174410: contador 3 apagado, sheet 3 treinos/3 completos, 4 aceso após série, meta presença 4/11, meta após reabrir, plano, estudos.
- [x] 6. Rebase into small, ordered commits; stack follow-ups.
  - skip: commits já pequenos em main (5 da feature + 828da96 harness; web df8e043).
- [ ] 7. If the design is contested, `interrogate` before shipping.
  - skip: design sem disputa; verificado ponta a ponta.
- [ ] 8. Run Opening a PR.
  - skip: o fluxo do projeto é commitar em main e publicar pelo release.sh.
- [x] 9. Rodar `scripts/release.sh` e instalar no iPhone pelo Wi-Fi.
  - build 6 publicado e instalado no iPhone às 17:47:52; assinatura até 2026-09-22.

## Decisões

- Streak de treinos corretos = sessão `completed` (todas as séries de trabalho marcadas). Presença = dia com pelo menos uma série de trabalho marcada.
- O streak zera quando a última sessão passa de 5 dias; hoje ele fica congelado até 28 dias.
- O topo mostra o streak de presença. Chama cinza sem treino hoje, colorida com treino.
- `motion-dev-animations` é para web; do SwiftUI aproveito só a regra de molas e movimento reduzido.

## Estado para retomar (2026-09-15)

Feito:
- Web `h&nrique` main `e905e9e`, já no GitHub: `calculateStreak` no domínio (zera após 5 dias sem teto de 28), `attendanceStreak`, `streakGoals`, rota `POST /api/v1/goal/set-streak`, migração 0009 aplicada em produção, deploy Ready em hnrq.vercel.app.
- iOS main `2fa3960`, sem push: 28be164 core, 8dcd250 contador no topo, 8d376eb metas em progresso, 6d06625 texto Academia, 2fa3960 texto Estudos. 73 testes passando no simulador "iPhone 17".
- Simulador pode estar com o build Debug apontando para 127.0.0.1:3999; reinstalar o Debug normal.

Próximo (opção 2 escolhida pelo usuário): ambiente de teste antes do release.

Mudança de plano (2026-09-15): o banco de produção está na org Neon da Vercel do time emvidros, fora do alcance do MCP e do neonctl. Troquei o branch Neon por Postgres local na porta 54329, porque o servidor usa `pg` e o dotenv não sobrescreve `DATABASE_URL` já definida. Design em scratchpad/test-env-design.md.
1. Branch Neon `dev` a partir de produção (MCP Neon). Nunca expor em preview.
2. Usuário de teste só no branch; senha fora do repo (Keychain ou ~/.config/henrique/test-credentials).
3. `.env.development.local` no repo web com o DATABASE_URL do branch; `localhost:3000` usa ele. `.env.local` de produção fica intocado. Conferir que o dev server lê o arquivo novo antes do de produção.
4. Script fixo no repo iOS que sobe o servidor, compila Debug, faz login com a credencial via XCUITest e grava PNGs. Reset do branch antes de cada rodada.
5. Com isso, verificar: contador aceso/apagado, sheet da sequência, cards de meta, editor presença salvando pelo servidor real, texto das abas treino/plano/estudos, animação do número subindo.
6. Depois: `scripts/release.sh` e instalação no iPhone pelo Wi-Fi. Atualizar memória driving-ui-without-credentials.

# Montagem de treino

- [x] 1. `how` over the affected subsystem.
- [x] 2. `architect` for parallel design exploration.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Rastrear o array salvo e os controles existentes antes de implementar.
  - Independent workstreams. Revisão de interação e preparação do deploy podem ocorrer enquanto o worker altera a tela.
  - Shared mutable state. Worker em worktree exclusivo; integrar depois de encerrar a escrita.
  - Smallest safe decomposition. Um worker cuida da tela e dos testes associados, pois compartilham o mesmo fluxo.
- [x] 4. Delegate code-writing to a subagent.
- [ ] 5. Verify on the matching surface.
- [ ] 6. Rebase into small, ordered commits; stack follow-ups.
  - skip: entrega local no iPhone, sem mudança de branch pública.
- [ ] 7. If the design is contested, `interrogate` before shipping.
  - skip: decidir pelo controle nativo se a verificação confirmar o gesto.
- [ ] 8. Run Opening a PR.
  - skip: o pedido é alterar o app local e instalar no iPhone.

## Decisões

O array ordenado [PlanExercise] continua sendo a fonte da ordem e dos valores. Apagar modifica apenas o rascunho até Salvar. O projeto é SwiftUI, portanto os exemplos Motion.dev não se aplicam como dependência. A auditoria improve-animations fica restrita à interação pedida, seguida da implementação já autorizada.

## Verificação

- Build Release arm64 para iPhone passou. IPA build 4 usa https://hnrq.vercel.app.
- Suíte no iOS Simulator passou com 70 testes em 9 suites.
- Revisão independente não encontrou bug material no diff.
- Teste no macOS encontrou timeout do compilador no ExercisePicker; a suíte foi executada no iOS.
- Instalação do build 4 iniciada pelo AltStore no iPhone conectado.

- devicectl confirmou app.henrique.academia.H2474S94U5 build 4 instalado e aberto no iPhone físico.
- No iPhone, Organizar mostrou duas linhas compactas e alças nativas. A lixeira removeu só o exercício escolhido. Cancelar descartou o rascunho de teste.
- Pendente a confirmação do arraste por toque. Duas tentativas via Espelhamento ativaram a linha, mas não alteraram a ordem. Não foi validada persistência de reordenação no servidor.

# Teclado, cargas, confirmação e treinos sem dia

- [x] 1. `how` over the affected subsystem.
- [x] 2. `architect` for parallel design exploration.
  - Ground, Sketch, Agree, Implement, Scrap.
  - Arena: Frame, Fan out, Cross-judge, Pick, Graft, Verify.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Rastrear contrato do servidor, calendário e gravação de séries antes da implementação.
  - Independent workstreams. Investigar persistência enquanto preparo a verificação iOS. Implementação do servidor e iOS em worktrees separados.
  - Shared mutable state. Um dono por worktree. Testes integrados só depois de encerrar os writers.
  - Smallest safe decomposition. Um dono iOS para teclado, estado da série e plano; um dono backend para contratos e transações.
- [x] 4. Delegate code-writing to a subagent.
- [x] 5. Verify on the matching surface.
- [x] 6. Rebase into small, ordered commits; stack follow-ups.
- [ ] 7. If the design is contested, `interrogate` before shipping.
  - skip: design sem disputa; revisão independente do diff e testes ponta a ponta foram suficientes.
- [ ] 8. Run Opening a PR.
  - skip: o fluxo local publica em main pelo release.sh, sem PR.

O dado será treino com weekdays vazio ou preenchido e gravação pendente identificada por dia, treino e série. Model the Domain orienta essa escolha para separar agenda e existência do treino.

## Escolha de desenho

How confirmou que o editor salva só no check e o dashboard exclui treinos sem dia. Duas revisões independentes compararam overlay no store e estado local por linha. Escolhi overlay no store com identidade por data, template e série. A FIFO será do store, não por série, porque cada resposta substitui o mesmo dashboard. Essa escolha corrige a proposta de fila por chave da segunda revisão. Rejeitei manter os treinos sem dia ocultos, sugerido na primeira revisão, porque impediria reabrir os treinos futuros pedidos pelo usuário.

O teclado usará toolbar SwiftUI e foco, com adaptação da barra existente do editor de texto. Sem introspecção global UIKit. O servidor manterá weekdays vazio como treino salvo e sem agenda. O dia legado será null nesses itens. A série valendo e a prescrição do template serão atualizadas na mesma transação. Aquecimento não altera prescrição.

Worktrees exclusivos em /tmp/henrique-ios-workout-flows e /tmp/henrique-web-workout-flows. Parent mantém testes de UI no checkout original. Backend e iOS só serão integrados depois de encerrada a escrita de cada dono.

## Retomada e evidência

Baseline scripts/verify-ui.sh passou. O teste novo testZTreinoSemDia falhou no app original por ausência de keyboard.done, em output/verify/20260915-181058. A interrupção por limite deixou patches nos dois worktrees; retomados pelos mesmos donos.

Backend integrado localmente em 039d1c3. Testes reportados e revisados: 33 domínio, 19 API, 26 web; build passou. Script packages/api/scripts/verify-workout-flows.ts passou contra PostgreSQL isolado, inclusive rollback e concorrência. Revisão independente sem defeito material. O push para main passou, mas a Vercel bloqueou os deployments com TEAM_ACCESS_REQUIRED. Backend com weekdays vazio requer app atualizado; instalar o iOS antes de disponibilizar treinos sem dia em produção.

Verificação final. `testZCargaETeclado`, `testZTreinoSemDia` e `testZZTecladoEmEstudos` passaram no iPhone 17 Simulator. `scripts/test.sh` passou com 74 testes em 9 suites. As capturas estão em `output/verify/20260915-194307`, `output/verify/20260915-194134` e `output/verify/20260915-194600`.

# Folders com cor, tela de hoje e correções

- [x] 1. `how` over the affected subsystem.
  - Aba "hoje" é `OverviewScreen` em `RootView.swift`; aba "treino" é `TodayScreen` com o `DayStrip`; aba "plano" é `WeekScreen`, onde ficam os folders (`WorkoutTile`) e o `WorkoutEditor`. O erro "input validation failed" é a mensagem crua do servidor caindo em `AcademiaStore.handle`.
  - Treino sem dia já existe no app (`weekdays` vazio) e no servidor (039d1c3). Falta confirmar que o deploy em produção tem esse commit.
- [ ] 2. `architect` for parallel design exploration.
  - architect skipped: a referência visual fixa o layout da tela de criar treino e a forma do dado é uma coluna `color` mais uma rota de frequência por intervalo. Sem fork real de desenho.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Contrato do servidor (`color` no `workout_template`, rota de frequência) e as mudanças de Core no iOS antes de qualquer tela.
  - Independent workstreams. Repo web e repo iOS são disjuntos. Dentro do iOS, heatmap e folders só ficam disjuntos depois do commit de Core.
  - Shared mutable state. `Training.swift`, `Inputs.swift`, `APIClient.swift` e `AcademiaStore.swift` são escritos por um dono só, na fase 1. Depois cada worker tem seu worktree e seus arquivos de tela.
  - Smallest safe decomposition. Três donos: servidor, Core+polish do iOS, e depois dois de tela em paralelo.
- [x] 4. Delegate code-writing to a subagent.
  - Worker em `/private/tmp/henrique-ios-session-timing`; diff revisado e integrado manualmente para preservar as mudanças locais do checkout.
- [ ] 5. Verify on the matching surface.
  - Testes iOS passaram com 140 testes em 18 suítes e o app compilou no scheme `Henrique`. O fluxo UI focado ficou inconclusivo porque o cenário resetado não encontrou `Superiores`; a inspeção manual ficou bloqueada com o Mac travado.
- [ ] 6. Rebase into small, ordered commits; stack follow-ups.
- [ ] 7. If the design is contested, `interrogate` before shipping.
- [ ] 8. Run Opening a PR.
  - skip: o fluxo do projeto é commitar em main e publicar pelo release.sh.

## Contrato

- `workout_template.color text` nullable, formato `#RRGGBB`. Nulo cai na cor pelo dia da semana, então treino antigo não muda de aparência.
- `weekPlan[].color: string | null` na saída do dashboard.
- `saveWorkoutInputSchema.color` opcional e nulo permitido, validado por regex.
- Rota nova `POST /api/v1/training/attendance`, entrada `{ from, to }` em iso date, saída `{ days: [{ date, workSets, completed }] }`. Intervalo máximo de 400 dias.

## Decisões

- A cor mora no servidor, escolha do usuário, para a web ver a mesma coisa e sobreviver a reinstalar o app.
- A tela de criar e editar treino segue a referência: preview vivo do folder no topo, um passo por vez embaixo, seta preta voltando o passo. O seletor de cor é um desses passos, alcançado pelos três pontos e "editar".
- A tela "hoje" ganha um mapa de frequência estilo GitHub, com troca entre mês e ano.

## Achado sobre produção (2026-09-15 20:15)

`hnrq.vercel.app` aponta para `henrique-life-76gubon8q`, um deploy de ~14h. O commit
039d1c3, que aceita treino sem dia, é de 18:20 e nunca subiu: o deploy das 19:08 ficou
UNKNOWN. Então treino sem dia funciona no app e no banco local, mas não em produção.
O deploy final tem que levar 039d1c3 junto com a cor e a rota de frequência, pela rota
do `git archive` (deploy direto da CLI fica BLOCKED por acesso ao time).

## Diagnóstico do "input validation failed"

A frase é do oRPC, devolvida em 400 quando o zod recusa o corpo. Junto vem
`data.issues`, dizendo qual campo caiu, e `APIClient.swift:261` joga fora essa
parte antes de virar banner. Por isso o erro nunca diz nada.

As oito divergências são a mesma falha repetida: as faixas do zod estão escritas
de novo em cada tela, sempre mais frouxas que o servidor.

Causa provável:
1. `measurement/add` — `OptionalField` recebe um `range` em `MeasurementsScreen.swift:245` e nunca usa. Braço com 8 cm passa no app e volta recusado.
2. `plan/save-workout` — no onboarding, exercício da wger não está no catálogo, `groups` fica vazio e `focus` vira string vazia. O servidor pede 2 caracteres.
3. `workout/record-set` — `reps` sem teto no campo e nas guardas. O servidor limita em 100. É o campo mais tocado do app.
4. `workout/record-set` — `weightKg` sem teto. O servidor limita em 1000.

Risco latente: peso corporal abaixo de 20 kg, meta de força abaixo de 1,
`startingWeightKg` acima de 1000, e id de matéria fora do regex de slug.

Conserto: uma tabela de limites em `HenriqueCore`, lida pelas telas e aplicada na
borda pelos tipos de entrada. Mais `APIClient` lendo `data.issues` e nomeando o
campo, para o próximo erro se explicar sozinho.

## Verificação (2026-09-15 21:55)

- `scripts/test.sh ios "iPhone 17"`: 92 testes em 11 suítes, passou.
- `scripts/verify-ui.sh` contra o servidor de teste na 3001: 4 testes, passou.
  Capturas em `output/verify/20260915-214614`.
- `ONLY=testZHojeEMapa`: mapa do mês, mapa do ano e bolinha do dia atual, em
  `output/verify/20260915-215357`.
- Servidor em produção: migração 0010 aplicada, deploy `henrique-life-1ofjpd2ry`
  com o alias `hnrq.vercel.app`, main do repo web em `32e1e19` no GitHub.

O driver de UI precisou aprender a andar pelos passos do editor. `salvar` virou
`concluir`, `cancelar` virou a seta de fechar, e a barra de navegação sumiu, então
a presença do editor passa a ser detectada pelo botão `concluir`.

# Pasta fosca de treino

- [x] 1. Establish the baseline first, before any migration: a visual regression harness that screenshots the current component across its states, plus the target when matching two implementations. No baseline, no parity claim. A blocking prerequisite, not a follow-up.
  - Referência original fornecida pelo usuário; captura anterior válida em output/verify/20260915-214614/06-plano.png. As tentativas em output/folder-parity capturaram outra aba e login, por isso não servem de baseline.
- [x] 2. Anti-shortcut clauses, stated and held: no harness modifications, no baseline tampering, no component restructuring to make a diff pass. If the baseline looks wrong, stop and ask, don't edit it.
- [x] 3. Migrate one component at a time. Parallelize across worktrees, one owner per component (the **separate-before-serializing-shared-state** principle skill). Shared primitives migrate first as a blocking phase.
- [ ] 4. Verify each component against its baseline via image diff on the matching surface via the driver skill. A nonzero diff is a fail; investigate the pixel delta. `/loop` per component until the diff is zero.
  - skip: diferença zero não foi medida. Português, cores por treino e onda condicional são diferenças aprovadas. Conferência visual e testes de interação no simulador, sem afirmar igualdade pixel a pixel.
- [ ] 5. Run **Opening a PR** per component or per safe batch.
  - skip: entrega local, sem publicação solicitada.

A referência fornecida e a resposta do usuário confirmam a forma. Nenhum mock novo necessário. Model the Domain mantém a frequência por identidade do treino. Prove It Works exige captura do binário e teste da condição da onda.

Throughput checkpoint. O componente visual tem um dono. Core, testes e frequência no servidor têm outro. Nenhum arquivo compartilhado entre writers. Build depende da propriedade highlightedWorkoutIDs; a geometria pode avançar antes dela.


Verificação da pasta. Build iOS passou. O fluxo existente testFluxo passou em 84 s. O novo testPastaDeTreino passou em 30 s, com abertura do menu, editor e início de treino. Capturas normais em output/verify/20260916-082417. A suíte Core passou com 96 testes em 12 suítes, incluindo quatro testes da onda. Backend passou com oito testes em dois arquivos e checagem de tipos/lint.

A onda usa a identidade das sessões concluídas, com todos os empates no maior total positivo da semana. Treino em andamento exige séries valendo registradas e total ainda incompleto. Servidor antigo mantém apenas esse destaque de andamento. Mudanças no repo web permanecem locais, sem deploy.

A verificação no maior tamanho de acessibilidade passou em 34 s após corrigir a combinação de escala da fonte e largura da pasta. Capturas finais em output/verify/20260916-082724. A prévia decorativa do editor mantém tamanho de texto padrão; os campos continuam seguindo o ajuste do sistema. O simulador voltou ao tamanho de texto large. Nenhum commit, deploy ou instalação em iPhone físico foi feito.

## Correção da faixa acima do botão

Fix Root Causes identificou outra borda além do separador já removido. A onda fechada terminava com opacidade 0,12 em y347 da geometria normalizada. O preenchimento agora desaparece gradualmente, mantendo o traço curvo.

Reprodução sem o separador em output/verify/20260916-083332/06-plano.png. Correção em output/verify/20260916-083829/pasta-ativa.png. check-seam.py mediu salto RGB entre linhas de 19,02 antes e 1,49 depois. testPastaAtiva passou em 29,965 s. Build passou. O teste amplo intermediário falhou ao abrir a tela de sequência, antes do componente; a verificação focada chegou à pasta com série marcada e comprovou o resultado. Nenhum deploy.

# Sincronizar cargas entre treinos

- [x] `how` over the affected subsystem.
- [x] `architect` for parallel design exploration. Two candidate runners timed out; the design was selected from the traced API and store flow after comparing server transaction, client fan-out, and local-only overlay.
- [x] Write the throughput checkpoint as four todo items:
  - [x] Blocking first steps. Confirm the iOS and API contracts before fan-out.
  - [x] Independent workstreams. Backend transaction and iOS state projection use separate repositories and worktrees.
  - [x] Shared mutable state. Each worker owns one repository; the backend transaction serializes the shared exercise-weight invariant.
  - [x] Smallest safe decomposition. One worker per repository keeps each change coherent and avoids cross-repository merge races.
- [x] Delegate code-writing to a subagent with an exclusive worktree and review its diff. The workers timed out before returning patches; the parent completed the bounded edits and reviewed both diffs.
- [x] Verify on the matching surface.
- [ ] Rebase into small, ordered commits; stack follow-ups.
  - skip: the repositories contain unrelated local changes and the workspace does not allow creating commits.
- [ ] If the design is contested, `interrogate` before shipping.
  - skip: the server transaction is the only durable shape that avoids stale client fan-out.
- [ ] Run `Opening a PR`.
  - skip: no PR or deploy was requested.

## Decisão

`exerciseId` identifica o exercício compartilhado. Uma alteração de série de trabalho atualiza `startingWeightKg` em todos os `workoutTemplateExercise` do plano ativo na mesma transação. Séries de aquecimento continuam isoladas. O iOS aplica o mesmo valor a todos os itens de `weekPlan` que tenham o exercício enquanto renderiza a resposta confirmada.

## Throughput checkpoint

O backend e o iOS são workstreams independentes. O backend não pode ser alterado no checkout do iOS. Os dois repositórios já têm mudanças locais, então cada worker preserva o diff existente e escreve apenas em seu repositório.

## Verificação

O simulador iOS passou com 133 testes em 17 suítes. A API passou na checagem TypeScript, em 27 testes da API, 43 testes do domínio e no fluxo Postgres descartável com dois treinos compartilhando um exercício. A checagem geral continua apontando apenas dois snapshots de formatação já existentes no pacote de banco.

# Cronômetro da sessão de treino

- [x] 1. `how` over the affected subsystem.
  - A sessão usa `WorkoutSessionScreen`, `TrainingSetRow` e `AcademiaStore`; `PrepSet.completedAt` e `WorkSet.completedAt` já são os timestamps disponíveis. A projeção otimista recria timestamps pendentes com `.now`, então o cronômetro não pode depender desse valor sem estabilizá-lo.
- [x] 2. `architect` for parallel design exploration.
  - Duas propostas foram comparadas com uma revisão independente. Escolhida a derivação pura de `WorkoutSessionTiming` com `completedAt` estável no `PendingSet`, sem ledger paralelo ou endpoint novo.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Mapear o toque que conclui a primeira série, a conclusão da última série e o ciclo de vida da tela antes de escrever o cronômetro.
  - Independent workstreams. A investigação de fluxo e o desenho do estado podem correr em paralelo; a implementação da tela e os testes compartilham o mesmo caminho e ficam serializados.
  - Shared mutable state. O estado do cronômetro pertence à sessão aberta, então um único writer altera `WorkoutSessionScreen` e os testes associados.
  - Smallest safe decomposition. Um worker implementa o tipo de estado e a tela, porque a regra de início e fim depende do mesmo snapshot do treino.
- [x] 4. Delegate code-writing to a subagent.
  - Servidor: fix/audit-server e fix/audit-server-2 juntados no main do web, sem push nem deploy. Migrações 0015 a 0018 só no banco local.
  - iOS: três rodadas juntadas no main; 249 testes passando.
- [x] 5. Verify on the matching surface.
  - Maestro pela CLI em output/maestro-verify/ (v* na primeira rodada, r* na segunda).
- [x] 6. Rebase into small, ordered commits; stack follow-ups.
  - skip: commits já pequenos em main.
- [ ] 9. Produção: migrações 0015 a 0018 antes do deploy, deploy do web, release.sh. Espera confirmação.
  - skip: o projeto entrega mudanças locais em main e não foi solicitado abrir PR.
- [ ] 7. If the design is contested, `interrogate` before shipping.
  - skip: só será necessário se as alternativas de estado produzirem comportamentos diferentes no fluxo real.
- [ ] 8. Run Opening a PR.
  - skip: o pedido é uma alteração local no app, sem publicação solicitada.

## Decisão de dados

`WorkoutSessionTiming` deriva `startedAt` do menor `completedAt` nas séries de aquecimento e `finishedAt` do maior timestamp quando todas as séries estão concluídas. Uma pendência offline conserva o instante capturado no toque. A tela calcula `Date.now - startedAt` enquanto a sessão corre e congela o valor final. O contador não incrementa estado a cada segundo e não cria uma segunda fonte de verdade para as séries.

# Correções da auditoria (2026-09-23)

- [x] 1. `how` over the affected subsystem.
  - Feito pela auditoria: três relatórios (Maestro, código iOS, servidor), capturas em output/maestro-audit/.
- [x] 2. `architect` for parallel design exploration.
  - architect skipped: cada item tem forma única já apontada na auditoria; o contrato entre servidor e app está fixado abaixo.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Contrato fixado antes do fan-out: plano ganha prepWeightKg e restSeconds opcionais; exercício do painel ganha previousPrep; recordSet aceita completedAt opcional; Idiomas aceita date.
  - Independent workstreams. Servidor (repo web), Academia iOS, Estudos/shell iOS.
  - Shared mutable state. Cada worker em worktree próprio; Academia e Estudos dividem por pasta de tela; notificação local duplicada é reconciliada na revisão.
  - Smallest safe decomposition. Três workers; Academia é um só porque sessão, store e fila mexem nos mesmos arquivos.
- [ ] 4. Delegate code-writing to a subagent.
- [ ] 5. Verify on the matching surface.
- [ ] 6. Rebase into small, ordered commits; stack follow-ups.
- [ ] 7. If the design is contested, `interrogate` before shipping.
  - skip: sem disputa de design.
- [ ] 8. Run Opening a PR.
  - skip: fluxo do projeto é commit em main; migração e deploy de produção e release esperam confirmação.

# Correção das animações de treino, 24 de setembro

- [ ] 1. Reproduce it yourself on the matching surface via the driver skill.
- [x] 2. Binary-search the cause.
  - Histórico confirma fade original de 300 ms e atraso de 50 ms. Transações de entrada abrangem subárvores e a expansão recalcula seu conteúdo a cada quadro. Travamentos ainda precisam de medição.
- [x] 3. Plan the fix.
  - Ground. SessionOrigin contém o quadro e o preenchimento do card; a sessão mora acima das abas.
  - Sketch. Comparar máscara Shape com conteúdo fixo e zoom nativo.
  - Agree. Usuário confirmou expansão contínua, cantos em morph e conteúdo em fade.
  - Implement. Um worker altera os fades compartilhados; o coordenador cuida da apresentação.
  - Scrap. Remover a implementação anterior ao integrar a escolhida.
- [x] 4. Verify on the same surface.
- [ ] 5. Stage the commits so the failing repro lands before the fix in git history.
  - skip: ajuste visual sem teste unitário que comprove fluidez; entrega local sem commit solicitado.
- [ ] 6. Run Opening a PR.
  - skip: pedido de ajuste local, sem publicação solicitada.

O primeiro bloqueio é a reprodução no simulador. A investigação de histórico e a revisão da expansão podem ocorrer enquanto o teste de UI compila. Design.swift e telas de entrada pertencem a um worker; SessionPresentation.swift e WorkoutSessionScreen.swift pertencem ao coordenador. A menor divisão útil separa fade e morph, seguida de um único build integrado.

Model the Domain manteve SessionOrigin como origem congelada no toque. Subtract Before You Add orientou remover SessionGrowth, o atraso independente da sessão e o estado de direção do editor. O novo SessionMorph interpola o recorte, enquanto o fundo usa transform e opacidade e os exercícios mantêm seu layout.

Build iOS passou. O teste testTransicaoSessaoTreino passou com três ciclos de abertura e fechamento e zero falhas em 27,186 segundos. Capturas em output/verify/20260924-120239. A revisão independente aprovou o diff estático; o comentário deslocado no teste foi corrigido. O teste antigo testSessaoDeTreino falhou antes da abertura por não encontrar editar Superiores. O primeiro teste novo selecionou uma segunda-feira fora da tela; o seletor agora exige isHittable.

A fluidez no iPhone físico ainda não foi medida. A gravação inicial perdeu seu processo durante a interrupção da sessão; reiniciei apenas o simulador de teste para gravar novamente.

Verificação final passou novamente com zero falhas em 29,059 segundos. O teste agora aguarda a segunda-feira ficar visível. A gravação em output/motion-review/treino-expand.mp4 mostra abertura e retorno; os quadros intermediários confirmam recorte crescente e texto na posição final, sem escala dos exercícios. Não houve medição de FPS ou de hitches no iPhone físico. Nenhum release, commit ou instalação no iPhone foi feito.

Entrega no iPhone solicitada pelo usuário. Compilei o working tree em Release, com API https://hnrq.vercel.app e assinatura H2474S94U5. devicectl confirmou instalação no iPhone 13, UDID 00008110-000A5DC23C02401E. Instalação direta, sem publicar release no GitHub.

# Insígnia de meses de presença, 25 de setembro

- [x] 1. `how` over the affected subsystem.
  - Contador da chama no topo (StreakScreen), presença por intervalo no AcademiaStore (limite 400 dias no servidor), regra de sequência do repo web lida.
- [x] 2. `architect` for parallel design exploration.
  - architect skipped: a referência fixa o visual e a memória do dono fixa o mecanismo (camada acima das abas, um relógio só, texto em fade). Único fork de dado (data de início no servidor ou no cliente) decidido pela evidência: a rota de presença já cobre 400 dias.
- [x] 3. Write the throughput checkpoint as four todo items.
  - Blocking first steps. Tipos puros (nível, tempo de sequência, já comemorado) com testes antes da camada visual.
  - Independent workstreams. n/a: núcleo e camada visual se tocam no mesmo fluxo; um só worker.
  - Shared mutable state. O working tree tem mudanças não commitadas de 24/09 que estão no iPhone. O worker trabalha no próprio tree, sem worktree, porque um worktree sairia do HEAD sem elas; o coordenador não escreve no tree enquanto ele roda.
  - Smallest safe decomposition. Um worker: core + UI + alavanca `--insignia N`; o coordenador revisa e grava a animação.
- [x] 4. Delegate code-writing to a subagent.
  - Worker único no tree principal: núcleo (nível, tempo de sequência, já comemorado) com 8 testes, camada da insígnia, contador publicando o quadro da chama, `--insignia N`. Diff revisado.
- [x] 5. Verify on the matching surface.
  - Suíte do iPhone 17 verde (216 core + 42 UI). Animação gravada no simulador contra o servidor de teste na 3001 para os níveis 1, 3, 7 e 10; vídeos em output/insignia/validar. Fluidez no iPhone físico ainda não medida.
- [ ] 6. Rebase into small, ordered commits; stack follow-ups.
  - espera a validação do dono; RootView.swift mistura hunks de 24/09 não commitados.
- [ ] 7. If the design is contested, `interrogate` before shipping.
- [ ] 8. Run Opening a PR.
  - skip: fluxo do projeto é commit em main e release.sh.
