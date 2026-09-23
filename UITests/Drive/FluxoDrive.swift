import XCTest

/// Quantos passos o editor de treino tem. O driver não importa o pacote, então
/// o número vive aqui e só muda quando `EditorStep` muda.
let EditorStepCount = 4

final class FluxoDrive: XCTestCase {
  let app = XCUIApplication(bundleIdentifier: "app.henrique.academia")
  let env = ProcessInfo.processInfo.environment
  var shots: String { env["HENRIQUE_SHOTS"] ?? NSTemporaryDirectory() }

  override func setUp() {
    continueAfterFailure = false
    try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
  }

  func shot(_ name: String) {
    let data = XCUIScreen.main.screenshot().pngRepresentation
    FileManager.default.createFile(atPath: "\(shots)/\(name).png", contents: data)
  }

  func launch(aba: String = "treino") {
    app.terminate()
    app.launchArguments = ["--app", "academia", "--aba", aba]
    app.launch()
    let user = app.textFields["usuário"]
    if user.waitForExistence(timeout: 4) {
      let banner = app.alerts.buttons["ok"]
      if banner.waitForExistence(timeout: 1) { banner.tap() }
      guard let username = env["HENRIQUE_TEST_USERNAME"], let password = env["HENRIQUE_TEST_PASSWORD"] else {
        XCTFail("faltam HENRIQUE_TEST_USERNAME e HENRIQUE_TEST_PASSWORD no ambiente")
        return
      }
      user.tap()
      user.typeText(username)
      let pass = app.secureTextFields["senha"]
      pass.tap()
      pass.typeText(password)
      app.buttons["entrar"].tap()
    }
    let counter = app.buttons["sequência"]
    XCTAssert(counter.waitForExistence(timeout: 15), "painel carregou depois do login")
    // O iOS oferece guardar a senha depois do primeiro login de cada instalação.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for notNow in [app.buttons["Not Now"], springboard.buttons["Not Now"]] where notNow.waitForExistence(timeout: 3) {
      notNow.tap()
      break
    }
    let setup = app.buttons["fechar"]
    if setup.waitForExistence(timeout: 1) { setup.tap() }
  }

  /// O plano semeado não tem treino em toda terça, quinta, sábado e domingo.
  /// Quando hoje cai num desses dias, o fluxo põe o dia no primeiro treino do
  /// plano, pelo mesmo editor que o usuário usa.
  func ensureWorkoutToday() {
    guard app.staticTexts["sem exercícios"].waitForExistence(timeout: 3) else { return }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    let names = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
    let today = names[calendar.component(.weekday, from: Date()) - 1]
    app.tabBars.buttons["plano"].tap()
    let menu = app.buttons["editar Superiores"]
    XCTAssert(menu.waitForExistence(timeout: 8), "plano listou Superiores")
    menu.tap()
    let editar = app.buttons["editar"]
    XCTAssert(editar.waitForExistence(timeout: 3), "menu do treino abriu")
    editar.tap()
    XCTAssert(app.staticTexts["nome e foco"].waitForExistence(timeout: 3), "editor de Superiores abriu")
    goToStep("dias")
    let day = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", today)).firstMatch
    XCTAssert(day.waitForExistence(timeout: 3), "dia \(today) visível no editor")
    day.tap()
    app.buttons["concluir"].tap()
    XCTAssert(app.buttons["concluir"].waitForNonExistence(timeout: 10), "editor fechou depois de salvar")
    app.tabBars.buttons["treino"].tap()
    XCTAssert(app.buttons["Concluir série 1"].firstMatch.waitForExistence(timeout: 10), "treino de hoje apareceu com séries")
  }

  /// O editor mostra um passo por vez. Toca em "avançar" até o título ser o
  /// pedido, e falha em vez de rodar para sempre se o passo não chegar.
  func goToStep(_ title: String) {
    for _ in 0..<EditorStepCount where !app.staticTexts[title].exists {
      let next = app.buttons["avançar"]
      guard next.exists, next.isEnabled else { break }
      next.tap()
    }
    XCTAssert(app.staticTexts[title].waitForExistence(timeout: 3), "editor chegou no passo \(title)")
  }

  func counterValue() -> String { app.buttons["sequência"].value as? String ?? "" }

  func replaceText(_ field: XCUIElement, with text: String) {
    // O toque duplo sozinho às vezes só põe o cursor, e aí o texto novo entra
    // na frente do velho. Focar primeiro e só então selecionar a palavra é o
    // que faz a digitação substituir o que estava lá.
    field.tap()
    XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 3), "teclado abriu no campo")
    field.doubleTap()
    field.typeText(text)
    XCTAssertEqual(field.value as? String, text, "o campo ficou com o texto novo")
  }

  func dismissKeyboard() {
    let done = app.buttons["keyboard.done"]
    let localizedDone = app.buttons["concluído"]
    XCTAssert(done.waitForExistence(timeout: 2) || localizedDone.waitForExistence(timeout: 2), "teclado tem botão nativo para concluir")
    (done.exists ? done : localizedDone).tap()
    XCTAssert(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "concluir fecha o teclado")
  }

  func testZCargaETeclado() {
    launch()
    ensureWorkoutToday()
    let weight = app.textFields["set.supino-inclinado.work.1.weight"]
    XCTAssert(weight.waitForExistence(timeout: 5), "carga da série valendo está disponível")
    let completion = app.buttons["set.supino-inclinado.work.1.completion"]
    let previousLabel = completion.label
    replaceText(weight, with: "37,5")
    shot("10-teclado-carga")
    dismissKeyboard()
    XCTAssertEqual(completion.label, previousLabel, "editar carga preserva conclusão da série")

    app.tabBars.buttons["plano"].tap()
    app.buttons["editar Superiores"].tap()
    app.buttons["editar"].tap()
    goToStep("exercícios")
    let planWeight = app.textFields["Carga em kg"].firstMatch
    XCTAssert(planWeight.waitForExistence(timeout: 5), "editor mostra carga do plano")
    let updated = NSPredicate(format: "value == %@", "37,5")
    expectation(for: updated, evaluatedWith: planWeight)
    waitForExpectations(timeout: 10)
    shot("11-carga-no-plano")
    app.buttons["fechar"].tap()

    launch()
    XCTAssert(weight.waitForExistence(timeout: 10), "série reaparece depois de abrir o app")
    XCTAssertEqual(weight.value as? String, "37,5", "carga persiste depois de reabrir")
    XCTAssertEqual(completion.label, previousLabel, "conclusão também persiste")
    completion.tap()
    XCTAssertNotEqual(completion.label, previousLabel, "check responde ao toque")
    shot("12-check")
  }

  func testZTreinoSemDia() {
    launch(aba: "semana")
    app.tabBars.buttons["plano"].tap()
    app.buttons["novo treino"].tap()
    let name = app.textFields["nome"]
    XCTAssert(name.waitForExistence(timeout: 5), "editor de treino abriu")
    name.tap()
    name.typeText("Treino futuro de teste")
    let focus = app.textFields["foco"]
    focus.tap()
    focus.typeText("Adaptação")
    dismissKeyboard()
    goToStep("escolha a cor")
    shot("13a-cor-do-treino-novo")
    goToStep("exercícios")
    app.buttons["adicionar"].tap()
    let search = app.textFields["Buscar exercício"]
    XCTAssert(search.waitForExistence(timeout: 5), "busca de exercícios abriu")
    search.tap()
    search.typeText("Supino inclinado")
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'supino inclinado'")).firstMatch.tap()
    let save = app.buttons["concluir"]
    XCTAssert(save.waitForExistence(timeout: 5) && save.isEnabled, "treino sem dia pode ser salvo")
    shot("13-treino-sem-dia-editor")
    save.tap()
    XCTAssert(app.buttons["concluir"].waitForNonExistence(timeout: 10), "treino sem dia foi salvo")
    shot("14-treino-sem-dia-plano")

    launch(aba: "semana")
    app.tabBars.buttons["plano"].tap()
    let tile = app.buttons["editar Treino futuro de teste, sem dia"]
    XCTAssert(tile.waitForExistence(timeout: 10), "treino sem dia continua no plano após reabrir")
    tile.tap()
    XCTAssert(app.staticTexts["nome e foco"].waitForExistence(timeout: 5), "toque no treino sem dia abre edição")
    goToStep("dias")
    app.buttons["sábado"].tap()
    app.buttons["concluir"].tap()
    XCTAssert(app.buttons["concluir"].waitForNonExistence(timeout: 10), "treino futuro recebeu um dia")
    XCTAssert(app.buttons["iniciar Treino futuro de teste, sábado"].waitForExistence(timeout: 5), "treino agendado pode ser iniciado")
    shot("15-treino-agendado")
  }

  func testZZTecladoEmEstudos() {
    launch()
    app.terminate()
    app.launchArguments = ["--app", "estudos", "--aba", "sessao"]
    app.launch()
    let note = app.textViews.firstMatch
    XCTAssert(note.waitForExistence(timeout: 10), "anotação da sessão abriu")
    if !note.isHittable { app.swipeUp() }
    note.tap()
    note.typeText("Primeira linha\nSegunda linha")
    XCTAssert((note.value as? String ?? "").contains("\n"), "retorno mantém quebra de linha no editor")
    shot("16-teclado-estudos")
    dismissKeyboard()
  }

  /// O mapa de frequência na aba "progresso" e a bolinha do dia atual na fita da
  /// aba "treino", que são as duas coisas que nenhum outro teste passa perto.
  func testZProgressoEMapa() {
    launch()
    ensureWorkoutToday()
    app.tabBars.buttons["progresso"].tap()
    let ano = app.buttons["frequencia.ano"]
    XCTAssert(ano.waitForExistence(timeout: 10), "mapa de frequência apareceu")
    sleep(2)
    shot("20-progresso-ano")
    // A última casa com treino é a mais perto de hoje, que é a que a fita do ano
    // mostra ao abrir.
    let dias = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'série'"))
    if dias.firstMatch.waitForExistence(timeout: 3), let dia = dias.allElementsBoundByIndex.last {
      dia.tap()
      sleep(1)
      shot("21-progresso-balao")
    }
    let mes = app.buttons["frequencia.mes"]
    mes.tap()
    XCTAssert(mes.waitForExistence(timeout: 3), "mapa trocou para o mês")
    sleep(2)
    shot("22-progresso-mes")
    ano.tap()
    app.tabBars.buttons["treino"].tap()
    XCTAssert(app.buttons["Voltar uma semana"].waitForExistence(timeout: 10), "fita do calendário apareceu")
    shot("22-calendario-bolinha")
  }

  /// A home tem que dizer o que fazer hoje, quantos treinos da semana já saíram
  /// e quais músculos ficaram sem estímulo.
  func testHomeAderenciaEMusculos() {
    launch()
    ensureWorkoutToday()
    app.tabBars.buttons["hoje"].tap()
    XCTAssert(app.buttons["hoje.abrir"].waitForExistence(timeout: 10), "cartão do dia apareceu")
    shot("40-home-topo")

    XCTAssert(
      app.descendants(matching: .any)["hoje.aderencia"].waitForExistence(timeout: 5),
      "o cartão da semana apareceu")

    let semana = app.buttons["musculos.week"]
    XCTAssert(semana.waitForExistence(timeout: 5), "mapa muscular apareceu")
    app.swipeUp()
    app.swipeUp()
    shot("41-home-musculos")

    app.buttons["musculos.month"].tap()
    XCTAssert(
      app.staticTexts["volume dos últimos 28 dias"].waitForExistence(timeout: 3),
      "o mapa troca para a janela de vinte e oito dias")
    shot("42-home-musculos-mes")
  }

  /// A fita dos próximos dias e os recordes. Duas seções que saem só do que o
  /// painel já mandava, e que a home nunca tinha mostrado.
  func testHomeProximosDiasERecordes() {
    launch()
    ensureWorkoutToday()
    app.tabBars.buttons["hoje"].tap()
    XCTAssert(app.buttons["hoje.abrir"].waitForExistence(timeout: 10), "cartão do dia apareceu")

    let plano = app.buttons["hoje.plano"]
    XCTAssert(plano.waitForExistence(timeout: 5), "a fita dos próximos dias apareceu")
    XCTAssert(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS 'hoje'")).firstMatch.waitForExistence(timeout: 3),
      "a fita marca o dia de hoje")
    shot("43-home-proximos-dias")

    plano.tap()
    XCTAssert(
      app.tabBars.buttons["plano"].isSelected,
      "o atalho da fita leva para a aba do plano")
  }

  func testPastaAtiva() {
    launch()
    ensureWorkoutToday()
    let sets = app.buttons.matching(identifier: "Concluir série 1")
    XCTAssert(sets.firstMatch.waitForExistence(timeout: 5))
    sets.allElementsBoundByIndex.last!.tap()
    XCTAssert(app.buttons["Desmarcar série 1"].firstMatch.waitForExistence(timeout: 5))
    app.tabBars.buttons["plano"].tap()
    XCTAssert(app.buttons["editar Superiores"].waitForExistence(timeout: 5))
    shot("pasta-ativa")
  }

  func testCalendarioDoPlano() {
    launch(aba: "semana")
    let feito = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', feito'"))
    XCTAssert(feito.firstMatch.waitForExistence(timeout: 8), "calendário pintou algum dia treinado")
    let mes = Date().formatted(.dateTime.locale(Locale(identifier: "pt_BR")).month(.wide).year())
    XCTAssert(app.staticTexts[mes].exists, "cabeçalho mostra \(mes)")
    shot("30-calendario-mes")
    app.buttons["Mês anterior"].tap()
    let anterior = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
      .formatted(.dateTime.locale(Locale(identifier: "pt_BR")).month(.wide).year())
    XCTAssert(app.staticTexts[anterior].waitForExistence(timeout: 3), "chevron levou a \(anterior)")
    shot("31-calendario-mes-anterior")
  }

  /// O modo treino atrás do botão do hero. Prova as três coisas que a tela de
  /// hoje não prova: a sessão abre, marcar série ali sobe o contador da sessão,
  /// e o descanso começa junto.
  func testSessaoDeTreino() {
    launch()
    ensureWorkoutToday()
    let start = app.buttons.matching(
      NSPredicate(format: "label IN {'começar', 'continuar'}")).firstMatch
    XCTAssert(start.waitForExistence(timeout: 8), "hero mostra o botão de começar o treino")
    start.tap()

    let close = app.buttons["sessao.fechar"]
    XCTAssert(close.waitForExistence(timeout: 5), "sessão abriu")
    shot("50-sessao")

    let counter = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH 'de ' AND label ENDSWITH ' séries'")).firstMatch
    XCTAssert(counter.waitForExistence(timeout: 3), "sessão mostra o total de séries")

    // Aquecimento e valendo têm o mesmo rótulo, e só a valendo move o contador.
    // O rótulo tem que ser "Concluir": um teste anterior pode ter deixado a
    // primeira valendo já marcada, e aí o toque desmarcaria.
    let check = app.buttons.matching(
      NSPredicate(format:
        "identifier CONTAINS '.work.' AND identifier ENDSWITH '.completion'"
        + " AND label BEGINSWITH 'Concluir'")).firstMatch
    XCTAssert(check.waitForExistence(timeout: 5), "sessão tem série valendo em aberto")
    let antes = doneCount()
    check.tap()
    XCTAssert(
      app.staticTexts["descanso"].waitForExistence(timeout: 3)
        && app.buttons["pular"].waitForExistence(timeout: 3),
      "marcar série valendo começa o descanso, com a contagem e o botão de pular")
    XCTAssertEqual(doneCount(), antes + 1, "o contador da sessão subiu uma série")
    shot("51-sessao-descanso")

    // A barra de descanso cobre o fim da lista, então ela sai antes do toque.
    app.buttons["pular"].tap()
    XCTAssert(app.buttons["pular"].waitForNonExistence(timeout: 3), "pular encerra o descanso")

    // A sessão virou lista: o exercício fechado é um cartão, e tocar nele abre.
    // Trocar de aparelho não depende mais de andar página por página.
    let fechado = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'sessao.exercicio.'")).firstMatch
    XCTAssert(fechado.waitForExistence(timeout: 3), "os outros exercícios aparecem recolhidos")
    // O exercício aberto ocupa a tela inteira, então os recolhidos ficam abaixo da
    // dobra. Tocar num elemento fora da tela erra o alvo sem falhar o toque.
    for _ in 0..<6 where !fechado.isHittable { app.swipeUp() }
    XCTAssert(fechado.isHittable, "o cartão recolhido chegou à tela")
    let id = fechado.identifier
    fechado.tap()
    XCTAssert(
      app.buttons[id].waitForNonExistence(timeout: 3),
      "tocar no cartão recolhido abre aquele exercício")
    shot("52-sessao-outro-exercicio")

    close.tap()
    XCTAssert(close.waitForNonExistence(timeout: 5), "sessão fechou")
    XCTAssert(
      app.buttons["Desmarcar série 1"].firstMatch.waitForExistence(timeout: 5)
        || start.waitForExistence(timeout: 5),
      "voltou para a tela de hoje com a marca da sessão")
  }

  /// Abre a sessão pelo hero e devolve o botão de fechar, que é o sinal de que
  /// ela está na tela.
  @discardableResult
  func openSession() -> XCUIElement {
    let start = app.buttons.matching(
      NSPredicate(format: "label IN {'começar', 'continuar'}")).firstMatch
    XCTAssert(start.waitForExistence(timeout: 8), "hero mostra o botão do treino")
    start.tap()
    let close = app.buttons["sessao.fechar"]
    XCTAssert(close.waitForExistence(timeout: 5), "sessão abriu")
    return close
  }

  /// Rola até o elemento ficar tocável. O exercício aberto ocupa a tela, então o
  /// que vem abaixo dele começa fora da dobra.
  func scrollTo(_ element: XCUIElement) {
    for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    XCTAssert(element.isHittable, "\(element.identifier) chegou à tela")
  }

  /// Quantas linhas valendo o exercício aberto desenha. Conta identificador
  /// distinto porque a árvore de acessibilidade devolve cada botão de série duas
  /// vezes, e contar elemento daria o dobro.
  func workRowCount(exerciseId: String) -> Int {
    let rows = app.buttons.matching(NSPredicate(format:
      "identifier CONTAINS %@ AND identifier CONTAINS '.work.' AND identifier ENDSWITH '.completion'",
      ".\(exerciseId)."))
    return Set((0..<rows.count).map { rows.element(boundBy: $0).identifier }).count
  }

  /// A contagem vem do servidor, então ela muda uma volta depois do toque.
  func waitForWorkRowCount(exerciseId: String, equals expected: Int, timeout: TimeInterval = 5) {
    let limit = Date().addingTimeInterval(timeout)
    while Date() < limit && workRowCount(exerciseId: exerciseId) != expected {
      _ = app.buttons.firstMatch.waitForExistence(timeout: 0.25)
    }
    XCTAssertEqual(
      workRowCount(exerciseId: exerciseId), expected, "a lista voltou a \(expected) linhas valendo")
  }

  /// O campo de anotação aceita mais de uma linha, e aí o iOS ora o publica como
  /// campo de texto, ora como área de texto.
  func noteField(exerciseId: String) -> XCUIElement {
    let id = "sessao.nota.\(exerciseId)"
    let field = app.textFields[id]
    return field.exists ? field : app.textViews[id]
  }

  /// Mais uma série, menos uma série, e a anotação que sobrevive a fechar e
  /// reabrir a sessão. Volta a contagem ao que era para os outros testes.
  func testSessaoSeriesENota() {
    launch()
    ensureWorkoutToday()
    let close = openSession()

    let add = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'sessao.adicionar-serie.'")).firstMatch
    XCTAssert(add.waitForExistence(timeout: 5), "o exercício aberto tem o botão de mais série")
    let exerciseId = add.identifier.replacingOccurrences(of: "sessao.adicionar-serie.", with: "")
    scrollTo(add)
    let antes = workRowCount(exerciseId: exerciseId)
    add.tap()
    let remove = app.buttons["sessao.remover-serie.\(exerciseId)"]
    XCTAssert(remove.waitForExistence(timeout: 5), "com a série nova em aberto aparece o botão de tirar")
    XCTAssertEqual(workRowCount(exerciseId: exerciseId), antes + 1, "a lista ganhou uma linha valendo")
    shot("53-sessao-mais-serie")

    remove.tap()
    waitForWorkRowCount(exerciseId: exerciseId, equals: antes)

    let note = noteField(exerciseId: exerciseId)
    XCTAssert(note.waitForExistence(timeout: 3), "o cartão aberto tem o campo de anotação")
    scrollTo(note)
    let texto = "pegada mais aberta \(Int(Date().timeIntervalSince1970) % 1000)"
    replaceText(note, with: texto)
    dismissKeyboard()
    shot("54-sessao-nota")

    close.tap()
    XCTAssert(close.waitForNonExistence(timeout: 5), "sessão fechou")
    openSession()
    let saved = noteField(exerciseId: exerciseId)
    XCTAssert(saved.waitForExistence(timeout: 5), "a sessão reabriu no mesmo exercício")
    XCTAssertEqual(saved.value as? String, texto, "a anotação voltou do servidor")
  }

  /// Um exercício só de hoje: entra pelo catálogo, ganha a marca e sai pelo
  /// menu dela. Sai sem série feita, então o servidor aceita tirar.
  func testSessaoExercicioSoHoje() {
    launch()
    ensureWorkoutToday()
    openSession()

    let add = app.buttons["sessao.adicionar-exercicio"]
    XCTAssert(add.waitForExistence(timeout: 5), "a lista termina no botão de mais exercício")
    scrollTo(add)
    add.tap()
    let search = app.textFields["sessao.buscar-exercicio"]
    XCTAssert(search.waitForExistence(timeout: 5), "o catálogo abriu com a busca")
    // A linha é um botão, e o SwiftUI funde o rótulo dos filhos nele, então
    // "Adicionar <nome>" fica no meio do rótulo e não no começo.
    let candidate = app.buttons.matching(
      NSPredicate(format: "label CONTAINS 'Adicionar '")).firstMatch
    XCTAssert(candidate.waitForExistence(timeout: 5), "o catálogo tem exercício fora do treino")
    let name = String(candidate.label.components(separatedBy: "Adicionar ")[1])
    search.tap()
    search.typeText(String(name.prefix(4)))
    XCTAssert(candidate.waitForExistence(timeout: 3), "a busca por nome mantém o exercício")
    shot("55-sessao-catalogo")
    candidate.tap()
    XCTAssert(search.waitForNonExistence(timeout: 5), "escolher fecha o catálogo")

    let chip = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'sessao.so-hoje.'")).firstMatch
    XCTAssert(chip.waitForExistence(timeout: 8), "o exercício novo abriu com a marca de só hoje")
    shot("56-sessao-so-hoje")
    let exerciseId = chip.identifier.replacingOccurrences(of: "sessao.so-hoje.", with: "")
    chip.tap()
    let remove = app.buttons["sessao.remover-exercicio.\(exerciseId)"]
    XCTAssert(remove.waitForExistence(timeout: 3), "a marca abre o menu com tirar de hoje")
    remove.tap()
    XCTAssert(chip.waitForNonExistence(timeout: 8), "tirar de hoje some com o exercício")
    XCTAssertFalse(app.buttons["sessao.exercicio.\(exerciseId)"].exists, "e ele não fica recolhido na lista")
  }

  /// Continuar tem que reabrir no exercício em aberto, não no começo. Roda por
  /// último porque termina um exercício inteiro, e os outros testes contam
  /// treinos e séries do mesmo banco.
  func testZContinuarTreino() {
    launch()
    ensureWorkoutToday()

    let hero = app.buttons.matching(
      NSPredicate(format: "label IN {'começar', 'continuar'}")).firstMatch
    XCTAssert(hero.waitForExistence(timeout: 8), "hero tem o botão do treino")
    hero.tap()

    let close = app.buttons["sessao.fechar"]
    XCTAssert(close.waitForExistence(timeout: 5), "sessão abriu")
    // Fecha o primeiro exercício inteiro. Só o exercício aberto desenha linha de
    // série, então o filtro já cai nele; `isHittable` continua separando a linha
    // visível da que rolou para fora da tela.
    let abertas = NSPredicate(format:
      "identifier CONTAINS '.work.' AND identifier ENDSWITH '.completion'"
      + " AND label BEGINSWITH 'Concluir'")
    let valendo = app.buttons.matching(abertas)
    XCTAssert(valendo.firstMatch.waitForExistence(timeout: 5), "sessão tem série em aberto")
    for _ in 0..<8 {
      guard valendo.firstMatch.isHittable else { break }
      let antes = doneCount()
      valendo.firstMatch.tap()
      waitForCount(antes + 1)
    }
    XCTAssertFalse(valendo.firstMatch.isHittable, "primeiro exercício terminou")
    close.tap()
    XCTAssert(close.waitForNonExistence(timeout: 5), "sessão fechou")

    let continuar = app.buttons["continuar"]
    XCTAssert(continuar.waitForExistence(timeout: 8), "o hero virou continuar")
    continuar.tap()
    XCTAssert(close.waitForExistence(timeout: 5), "sessão reabriu pelo continuar")
    shot("60-continuar-onde-parou")
    XCTAssert(
      valendo.firstMatch.waitForExistence(timeout: 5) && valendo.firstMatch.isHittable,
      "continuar abre um exercício com série em aberto, não o que já terminou")
  }

  /// Espera o contador da sessão chegar no valor. Ler logo depois do toque pega
  /// o número antes da transição, e o teste acusa marca perdida que não houve.
  func waitForCount(_ alvo: Int, timeout: TimeInterval = 4) {
    let contador = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES '^[0-9]+$'")).firstMatch
    expectation(
      for: NSPredicate(format: "label == %@", String(alvo)), evaluatedWith: contador)
    waitForExpectations(timeout: timeout)
  }

  /// As séries já feitas, lidas da legenda "N de M séries" do topo da sessão.
  func doneCount() -> Int {
    let label = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES '^[0-9]+$'")).firstMatch
    return Int(label.label) ?? -1
  }

  func testPastaDeTreino() {
    launch(aba: "semana")
    let menu = app.buttons["editar Superiores"]
    XCTAssert(menu.waitForExistence(timeout: 8))
    shot("pasta-plano")
    menu.tap()
    let edit = app.buttons["editar"]
    XCTAssert(edit.waitForExistence(timeout: 3))
    edit.tap()
    XCTAssert(app.staticTexts["nome e foco"].waitForExistence(timeout: 3))
    shot("pasta-editor")
    app.buttons["fechar"].tap()
    XCTAssert(menu.waitForExistence(timeout: 3))
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'iniciar '")).firstMatch.tap()
    XCTAssert(app.tabBars.buttons["treino"].isSelected)
  }

  /// A aba de entregas com o calendário do mês, o status do sync e a linha do
  /// Apple Calendar. Vale com e sem entregas semeadas, porque o calendário,
  /// o callout e a linha existem nos dois casos.
  func testZEntregasECalendario() {
    launch()
    app.terminate()
    app.launchArguments = ["--app", "estudos", "--aba", "entregas"]
    app.launch()
    XCTAssert(
      app.staticTexts["entregas"].waitForExistence(timeout: 15), "aba de entregas abriu")
    XCTAssert(
      app.buttons["Mês anterior"].waitForExistence(timeout: 8),
      "calendário de entregas apareceu")
    let nunca = app.staticTexts["o portal chega sozinho"]
    let sincronizado = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH 'sincronizado'")).firstMatch
    XCTAssert(
      nunca.waitForExistence(timeout: 3) || sincronizado.waitForExistence(timeout: 3),
      "status do sync visível")
    XCTAssert(app.staticTexts["Apple Calendar"].exists, "linha do Apple Calendar visível")
    shot("40-entregas-calendario")
    app.buttons["Próximo mês"].tap()
    shot("41-entregas-mes-seguinte")
    app.buttons["Mês anterior"].tap()
    XCTAssert(app.buttons["Mês anterior"].waitForExistence(timeout: 3), "voltou ao mês atual")
  }

  /// A aba de foco em idiomas: começa o alemão, para, vê o resultado e volta
  /// com o relógio do dia fora do zero.
  func testFoco() {
    launch()
    app.terminate()
    app.launchArguments = ["--app", "idiomas", "--aba", "foco"]
    app.launch()
    let start = app.buttons["começar alemão"]
    XCTAssert(start.waitForExistence(timeout: 15), "aba de foco abriu com o alemão na lista")
    shot("foco-01-home")
    start.tap()
    let stop = app.buttons["parar"]
    XCTAssert(stop.waitForExistence(timeout: 5), "cronômetro abriu")
    // Abaixo de 10 s a sessão não grava, então a espera passa disso.
    sleep(11)
    shot("foco-02-rodando")
    stop.tap()
    let close = app.buttons["fechar"]
    XCTAssert(close.waitForExistence(timeout: 5), "resultado apareceu")
    shot("foco-03-resultado")
    close.tap()
    XCTAssert(close.waitForNonExistence(timeout: 5), "resultado fechou")
    let clock = app.staticTexts["foco.relogio"]
    XCTAssert(clock.waitForExistence(timeout: 3), "relógio do dia visível")
    XCTAssertNotEqual(clock.label, "0 segundos hoje", "a sessão entrou no total de hoje")
    XCTAssert(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS '· alemão ·'")).firstMatch
        .waitForExistence(timeout: 3),
      "a sessão aparece na lista de hoje")
    shot("foco-04-depois")
    app.swipeUp()
    app.swipeUp()
    shot("foco-05-historico")
    app.terminate()
    app.launchArguments = ["--app", "estudos", "--aba", "hoje"]
    app.launch()
    XCTAssert(app.buttons["focar"].waitForExistence(timeout: 15), "cartão de foco na aba hoje de estudos")
    shot("foco-06-estudos")
  }

  func testFluxo() {
    launch()
    ensureWorkoutToday()
    XCTAssertEqual(counterValue(), "3 treinos", "contador começa com 3 do cenário")
    shot("01-treino")

    app.buttons["sequência"].tap()
    XCTAssert(app.navigationBars["sequência"].waitForExistence(timeout: 3), "tela de sequência abriu")
    XCTAssert(app.staticTexts["3 treinos, 3 completos"].waitForExistence(timeout: 3) || app.otherElements["3 treinos, 3 completos"].exists, "anel mostra 3 treinos e 3 completos")
    shot("02-sequencia")
    app.buttons["fechar"].tap()
    XCTAssert(app.navigationBars["sequência"].waitForNonExistence(timeout: 3), "tela de sequência fechou")

    // Aquecimento e valendo usam o mesmo rótulo; no card aberto o último é o valendo.
    XCTAssert(app.buttons["Concluir série 1"].firstMatch.waitForExistence(timeout: 5), "séries do primeiro exercício visíveis")
    let done = app.buttons.matching(identifier: "Concluir série 1").allElementsBoundByIndex.last!
    done.tap()
    shot("03b-toque")
    let lit = app.buttons["sequência"]
    let toFour = NSPredicate(format: "value == %@", "4 treinos")
    let wait = XCTNSPredicateExpectation(predicate: toFour, object: lit)
    shot("03c-toque")
    XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 10), .completed, "contador foi para 4 depois da série")
    XCTAssert(app.buttons["Desmarcar série 1"].firstMatch.waitForExistence(timeout: 3), "série valendo ficou marcada")
    shot("03-aceso")

    app.tabBars.buttons["progresso"].tap()
    let nova = app.buttons["nova meta"]
    XCTAssert(nova.waitForExistence(timeout: 5), "progresso abriu")
    nova.tap()
    XCTAssert(app.navigationBars["meta"].waitForExistence(timeout: 3), "editor de meta abriu")
    app.buttons["presença"].tap()
    let stepper = app.steppers.firstMatch
    XCTAssert(stepper.waitForExistence(timeout: 3), "campo alvo da presença visível")
    stepper.buttons["Increment"].tap()
    stepper.buttons["Increment"].tap()
    app.buttons["salvar"].tap()
    let card = app.buttons["meta de presença, 4 de 11"]
    XCTAssert(card.waitForExistence(timeout: 10), "card de meta de presença com 4 de 11")
    shot("04-meta")

    launch(aba: "progresso")
    XCTAssert(app.buttons["meta de presença, 4 de 11"].waitForExistence(timeout: 10), "meta continua depois de reabrir")
    shot("05-meta-reaberta")

    app.tabBars.buttons["plano"].tap()
    XCTAssert(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'iniciar '")).firstMatch.waitForExistence(timeout: 5), "plano listou treinos")
    shot("06-plano")

    app.tabBars.buttons["apps"].tap()
    let estudos = app.buttons["estudos"]
    XCTAssert(estudos.waitForExistence(timeout: 3), "painel de apps abriu")
    estudos.tap()
    XCTAssert(app.tabBars.buttons["matérias"].waitForExistence(timeout: 10), "estudos abriu")
    shot("07-estudos")
  }
}
