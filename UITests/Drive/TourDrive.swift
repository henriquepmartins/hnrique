import XCTest

/// Percorre as telas da Academia e salva uma captura de cada uma, para a
/// vistoria visual. Não prova comportamento: um passo que não acha o caminho
/// deixa a árvore de acessibilidade num .txt e o passeio segue.
///
/// O prefixo das capturas diz a condição: "padrao", "dt" quando o simulador está
/// num tamanho de texto de acessibilidade, e "pior" no passeio que antes cria
/// o treino de nome longo com 13 exercícios.
extension FluxoDrive {
  static let longWorkout = "Superiores com ênfase em deltoide posterior, bíceps e antebraço"
  static let longFocus = "Hipertrofia de membros superiores com pausa isométrica e cadência controlada na fase excêntrica"
  static let longExercise = "Remada unilateral no cabo com pegada neutra e pausa de dois segundos"

  func testZZZTourAcademia() {
    continueAfterFailure = true
    let dynamicType = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    tour(prefix: dynamicType ? "dt" : "padrao", workout: "Superiores")
  }

  func testZZZTourAcademiaPiorCaso() {
    continueAfterFailure = true
    launch()
    createWorstCaseWorkout()
    swapTodayTo(Self.longWorkout)
    tour(prefix: "pior", workout: Self.longWorkout)
  }

  private func tour(prefix p: String, workout: String) {
    launch()
    ensureWorkoutToday()

    app.tabBars.buttons["hoje"].tap()
    settle()
    shot("\(p)-01-home-topo")
    pages("\(p)-01-home", count: 3)

    app.tabBars.buttons["plano"].tap()
    settle()
    shot("\(p)-02-plano-topo")
    pages("\(p)-02-plano", count: 2)
    app.swipeDown(); app.swipeDown()

    let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "editar \(workout)")).firstMatch
    if found(edit, "\(p)-editor") {
      edit.tap()
      let editar = app.buttons["editar"]
      if editar.waitForExistence(timeout: 3) { editar.tap() }
      for (index, title) in ["nome", "cor", "dias", "exercícios"].enumerated() {
        goToStep(title)
        settle()
        shot("\(p)-03-editor-\(index + 1)-\(title)")
      }
      // Nada de swipeDown aqui: na folha ele arrasta o editor para fechar.
      let row = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS ' valendo'")).firstMatch
      if found(row, "\(p)-editor-exercicio") {
        row.tap()
        settle()
        shot("\(p)-03-editor-5-exercicio-aberto")
        row.tap()
        settle()
      }
      pages("\(p)-03-editor-4-exercicios", count: 4)
      let add = app.buttons["adicionar"]
      if found(add, "\(p)-seletor") {
        scrollToSoft(add)
        add.tap()
        settle()
        shot("\(p)-04-seletor")
        let search = app.textFields["Buscar exercício"]
        if search.waitForExistence(timeout: 3) {
          search.typeText("remada")
          settle(2.5)
          shot("\(p)-04-seletor-busca")
        }
        app.buttons["seletor.fechar"].tap()
      }
      app.buttons["fechar"].firstMatch.tap()
      let discard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'descartar'")).firstMatch
      if discard.waitForExistence(timeout: 2) { discard.tap() }
    }

    app.tabBars.buttons["treino"].tap()
    settle()
    shot("\(p)-05-treino-topo")
    pages("\(p)-05-treino", count: 2)
    app.swipeDown(); app.swipeDown()

    let sequence = app.buttons["sequência"]
    if found(sequence, "\(p)-sequencia") {
      sequence.tap()
      settle()
      shot("\(p)-06-sequencia")
      pages("\(p)-06-sequencia", count: 2)
      app.buttons["fechar"].firstMatch.tap()
    }

    let start = app.buttons.matching(NSPredicate(format: "label IN {'começar', 'continuar'}")).firstMatch
    if found(start, "\(p)-sessao") {
      start.tap()
      settle()
      shot("\(p)-07-sessao")
      let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sessao.historico.'")).firstMatch
      if found(history, "\(p)-historico") {
        history.tap()
        settle(2.5)
        shot("\(p)-09-historico")
        pages("\(p)-09-historico", count: 2)
        app.navigationBars.buttons.firstMatch.tap()
        settle()
      }
      let check = app.buttons.matching(NSPredicate(format:
        "identifier CONTAINS '.work.' AND identifier ENDSWITH '.completion' AND label BEGINSWITH 'Concluir'")).firstMatch
      if found(check, "\(p)-descanso") {
        check.tap()
        settle()
        allowNotifications()
        shot("\(p)-08-sessao-descanso")
      }
      let skip = app.buttons["pular"]
      if skip.exists { skip.tap() }
      pages("\(p)-07-sessao", count: 3)
      let addExercise = app.buttons["sessao.adicionar-exercicio"]
      if addExercise.exists {
        scrollToSoft(addExercise)
        shot("\(p)-07-sessao-fim")
      }
      app.buttons["sessao.fechar"].tap()
    }

    app.tabBars.buttons["progresso"].tap()
    settle(2)
    let nova = app.buttons["nova meta"]
    if found(nova, "\(p)-meta") {
      nova.tap()
      settle()
      shot("\(p)-10-meta-editor")
      let presence = app.buttons["presença"]
      if presence.waitForExistence(timeout: 2) { presence.tap() }
      app.buttons["salvar"].tap()
      settle(2)
    }
    app.swipeDown()
    shot("\(p)-11-progresso-topo")
    pages("\(p)-11-progresso", count: 5)

    let measures = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'medidas'")).firstMatch
    if found(measures, "\(p)-medidas") {
      scrollToSoft(measures)
      measures.tap()
      settle()
      shot("\(p)-13-medidas-vazio")
      app.buttons["nova medida"].tap()
      let weight = app.textFields["peso em kg"]
      if found(weight, "\(p)-medida-editor") {
        weight.tap()
        weight.typeText("82,4")
        let fat = app.textFields["gordura corporal em %"]
        fat.tap()
        fat.typeText("17,8")
        shot("\(p)-14-medida-editor")
        app.buttons["salvar"].tap()
        settle(2)
      }
      shot("\(p)-15-medidas")
      pages("\(p)-15-medidas", count: 2)
      app.navigationBars.buttons.firstMatch.tap()
      settle()
    }

    app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
    // O cartão do 1RM é um NavigationLink sem identificador, logo abaixo do
    // cartão de constância; o toque vai na área do gráfico, longe do menu do título.
    let consistency = app.descendants(matching: .any)["constância nas últimas 4 semanas"]
    if found(consistency, "\(p)-metrica") {
      for _ in 0..<6 where consistency.frame.minY > 300 { dragUp(0.3) }
      consistency.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 200)).tap()
      settle(2)
      shot("\(p)-12-metrica")
      pages("\(p)-12-metrica", count: 3)
      app.navigationBars.buttons.firstMatch.tap()
    }

    app.tabBars.buttons["hoje"].tap()
    if start.waitForExistence(timeout: 5) {
      start.tap()
      app.buttons["sessao.encerrar"].tap()
      let confirm = app.buttons["encerrar treino"]
      if confirm.waitForExistence(timeout: 3) { confirm.tap() }
      let summary = app.buttons["resumo.fechar"]
      if found(summary, "\(p)-resumo") {
        settle(2)
        shot("\(p)-16-resumo")
        pages("\(p)-16-resumo", count: 2)
        summary.tap()
      }
    }
  }

  /// O iOS pede permissão de notificação no primeiro descanso, e o alerta
  /// engole os toques seguintes.
  private func allowNotifications() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 2) { allow.tap(); settle() }
  }

  private func createWorstCaseWorkout() {
    app.tabBars.buttons["plano"].tap()
    app.buttons["novo treino"].tap()
    let name = app.textFields["nome"]
    XCTAssert(name.waitForExistence(timeout: 5), "editor de treino abriu")
    name.tap()
    name.typeText(Self.longWorkout)
    let focus = app.textFields["foco"]
    focus.tap()
    focus.typeText(Self.longFocus)
    shot("pior-00-editor-nome-longo")
    dismissKeyboard()
    goToStep("dias")
    let today = Self.weekdayNames[Self.saoPaulo.component(.weekday, from: Date()) - 1]
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", today)).firstMatch.tap()
    goToStep("exercícios")
    app.buttons["adicionar"].tap()
    let search = app.textFields["Buscar exercício"]
    XCTAssert(search.waitForExistence(timeout: 5), "busca de exercícios abriu")
    search.typeText(Self.longExercise)
    let create = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'criar'")).firstMatch
    XCTAssert(create.waitForExistence(timeout: 5), "a busca sem resultado oferece criar")
    shot("pior-00-seletor-criar")
    create.tap()
    settle()
    let addable = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Adicionar '"))
    var picked = 1
    // O limite do plano é 12; a 13ª tentativa mostra o que o seletor faz no teto.
    for _ in 0..<40 where picked < 13 {
      if app.keyboards.firstMatch.exists { search.typeText("\n") }
      if let next = addable.allElementsBoundByIndex.first(where: { $0.isHittable }) {
        next.tap()
        picked += 1
        settle(0.6)
        if picked == 12 { shot("pior-00-seletor-12") }
      } else {
        dragUp(0.35)
      }
    }
    shot("pior-00-seletor-cheio")
    app.buttons["seletor.fechar"].tap()
    shot("pior-00-editor-13-exercicios")
    app.buttons["concluir"].tap()
    XCTAssert(app.buttons["concluir"].waitForNonExistence(timeout: 10), "treino longo salvo")
  }

  /// Segura o card do dia e troca hoje pelo treino pedido, o mesmo gesto do
  /// usuário, para a sessão abrir com ele.
  private func swapTodayTo(_ workout: String) {
    app.tabBars.buttons["hoje"].tap()
    let card = app.descendants(matching: .any)["hoje.treino"]
    guard found(card, "pior-troca") else { return }
    if card.label.lowercased().hasPrefix(workout.lowercased()) { return }
    card.press(forDuration: 1.2)
    let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", String(workout.prefix(20)))).firstMatch
    guard found(option, "pior-troca-menu") else { return }
    option.tap()
    settle(2)
  }

  /// Existe, ou deixa a árvore do momento ao lado das capturas e devolve falso.
  @discardableResult
  private func found(_ element: XCUIElement, _ name: String) -> Bool {
    if element.waitForExistence(timeout: 6) { return true }
    FileManager.default.createFile(
      atPath: "\(shots)/nao-achou-\(name).txt", contents: Data(app.debugDescription.utf8))
    return false
  }

  private func dragUp(_ fraction: CGFloat) {
    let window = app.windows.firstMatch
    window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
      .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75 - fraction)))
    settle(0.6)
  }

  /// Arrasta devagar de baixo para cima pela borda direita. O swipe no meio da
  /// tela cai no mapa de frequência e não rola a página.
  private func pages(_ name: String, count: Int) {
    let window = app.windows.firstMatch
    for page in 2...count {
      window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
        .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.25)))
      settle(0.8)
      shot("\(name)-p\(page)")
    }
  }

  private func scrollToSoft(_ element: XCUIElement) {
    for _ in 0..<8 where !element.isHittable { app.swipeUp() }
  }

  private func settle(_ seconds: TimeInterval = 1.2) {
    Thread.sleep(forTimeInterval: seconds)
  }
}
