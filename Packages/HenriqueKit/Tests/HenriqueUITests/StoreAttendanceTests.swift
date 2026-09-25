import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

private func workKey(_ exercise: String, _ index: Int) -> SetKey {
  SetKey(date: .today, templateId: "tpl-terca", exerciseId: exercise, kind: .work, index: index)
}

private func attendanceBody(_ days: [(CalendarDate, Int)]) -> String {
  let items = days.map {
    #"{"date":"\#($0.0.iso)","workSets":\#($0.1),"completed":false,"workoutTemplateIds":["tpl-terca"]}"#
  }
  return #"{"days":[\#(items.joined(separator: ","))]}"#
}

/// O painel de hoje depois de desmarcar a única série valendo feita.
private func dashboardSemSerie() -> String {
  dashboardDeHoje()
    .replacingOccurrences(of: #""completedAt": "2026-09-08T13:09:40Z""#, with: #""completedAt": null"#)
    .replacingOccurrences(of: #""completedWorkSetCount": 1"#, with: #""completedWorkSetCount": 0"#)
}

@MainActor
private func planWeight(_ store: AcademiaStore) -> [Double?] {
  [
    store.dashboard?.weekPlan.first?.exercises.first?.startingWeightKg,
    store.dashboard?.workout?.exercises.first?.prescription.startingWeightKg,
  ]
}

extension PendingSetQueueTests {
  @Suite("A frequência e a carga do plano na store")
  @MainActor
  struct StoreAttendanceTests {
    init() {
      FakeNetwork.reset()
      resetLocalState()
    }

    @Test("desmarcar a única série de hoje tira o dia da frequência")
    func unmarkingClearsToday() async {
      let store = await lojaComPainel()
      let today = CalendarDate.today
      FakeNetwork.offline = false
      FakeNetwork.bodies[.attendance] = attendanceBody([(today, 1)])
      #expect(await store.loadAttendance(from: today.adding(days: -6), to: today))
      #expect(store.attendance[today]?.workSets == 1)

      FakeNetwork.bodies[.recordSet] = dashboardSemSerie()
      let outcome = await store.record(
        key: workKey("supino-reto", 1), weightKg: 42.5, reps: 9, completed: false, toFailure: true)?
        .value
      #expect(outcome == .applied)
      #expect(store.attendance[today] == nil)
    }

    @Test("a série gravada copia a presença do dia que o servidor mandou")
    func recordCopiesWeekAttendance() async {
      let store = await lojaComPainel()
      let today = CalendarDate.today
      FakeNetwork.offline = false
      FakeNetwork.bodies[.recordSet] = dashboardDeHoje().replacingOccurrences(
        of: #""onboardingCompleted": true"#,
        with: #""weekAttendance": [{"date": "\#(today.iso)", "workSets": 2, "completed": false, "workoutTemplateIds": ["tpl-terca", "outro"]}], "onboardingCompleted": true"#)
      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
        .value
      #expect(store.attendance[today]?.workSets == 2)
      #expect(store.attendance[today]?.workoutTemplateIds == ["tpl-terca", "outro"])
    }

    @Test("carregar de novo um intervalo já visto apaga o dia que sumiu")
    func reloadDropsVanishedDay() async {
      let store = await lojaComPainel()
      let today = CalendarDate.today
      let twoDaysAgo = today.adding(days: -2)
      let yesterday = today.adding(days: -1)
      FakeNetwork.offline = false
      FakeNetwork.bodies[.attendance] = attendanceBody([(twoDaysAgo, 3), (yesterday, 4)])
      #expect(await store.loadAttendance(from: today.adding(days: -6), to: today))
      #expect(store.attendance[twoDaysAgo]?.workSets == 3)

      FakeNetwork.offline = true
      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
        .value
      FakeNetwork.offline = false
      FakeNetwork.bodies[.attendance] = attendanceBody([(yesterday, 4)])
      #expect(await store.loadAttendance(from: today.adding(days: -6), to: today))
      #expect(store.attendance[twoDaysAgo] == nil)
      #expect(store.attendance[yesterday]?.workSets == 4)
    }

    @Test("a semana usa a frequência carregada, mesmo depois de marcar série")
    func trainingWeekUsesLoadedAttendance() async throws {
      let store = await lojaComPainel()
      let today = CalendarDate.today
      let monday = today.trainingWeekStart()
      #expect(Set(try #require(store.trainingWeek(today: today)).attended) == [today])

      FakeNetwork.offline = false
      FakeNetwork.bodies[.attendance] = attendanceBody([(monday, 3)])
      #expect(await store.loadAttendance(from: monday, to: today))
      #expect(Set(try #require(store.trainingWeek(today: today)).attended) == [monday, today])

      FakeNetwork.offline = true
      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
        .value
      #expect(Set(try #require(store.trainingWeek(today: today)).attended) == [monday, today])
    }

    @Test("o plano fica com a série mais pesada da sessão, não com a última")
    func planKeepsTheTopSet() async {
      let store = await lojaComPainel()
      #expect(planWeight(store) == [40, 40])

      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 38, reps: 10, completed: true, toFailure: true)?
        .value
      #expect(planWeight(store) == [42.5, 42.5])

      _ = await store.record(
        key: workKey("supino-reto", 2), weightKg: 45, reps: 8, completed: true, toFailure: true)?
        .value
      #expect(planWeight(store) == [45, 45])
    }

    @Test("a resposta do servidor antigo também fica com a série mais pesada")
    func acceptedDashboardKeepsTheTopSet() async {
      let store = await lojaComPainel()
      FakeNetwork.offline = false
      let outcome = await store.record(
        key: workKey("supino-reto", 2), weightKg: 38, reps: 10, completed: true, toFailure: true)?
        .value
      #expect(outcome == .applied)
      #expect(planWeight(store) == [42.5, 42.5])
    }
  }
}
