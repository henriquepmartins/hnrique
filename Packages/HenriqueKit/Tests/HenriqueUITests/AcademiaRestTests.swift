import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

private func workKey(_ exercise: String, _ index: Int) -> SetKey {
  SetKey(date: .today, templateId: "tpl-terca", exerciseId: exercise, kind: .work, index: index)
}

@Suite("O descanso")
struct RestStateTests {
  private let key = SetKey(
    date: CalendarDate(year: 2026, month: 9, day: 23)!, templateId: "tpl", exerciseId: "supino",
    kind: .work, index: 2)
  private let start = Date(timeIntervalSince1970: 1_000)

  @Test("o fim é o começo mais a duração")
  func endsAtMath() {
    let rest = RestState(key: key, startedAt: start, seconds: 90)
    #expect(rest.endsAt == Date(timeIntervalSince1970: 1_090))
    #expect(rest.total == 90)
    #expect(rest.remaining(at: Date(timeIntervalSince1970: 1_030)) == 60)
    #expect(rest.remaining(at: Date(timeIntervalSince1970: 1_200)) == 0)
    #expect(rest.fraction(at: Date(timeIntervalSince1970: 1_045)) == 0.5)
    #expect(!rest.isExpired(at: Date(timeIntervalSince1970: 1_095)))
    #expect(rest.isExpired(at: Date(timeIntervalSince1970: 1_096)))
  }

  @Test("±15 s mexe na duração inteira e fica entre 15 s e 10 min")
  func adjusts() {
    let rest = RestState(key: key, startedAt: start, seconds: 90)
    #expect(rest.adjusted(by: 15).endsAt == Date(timeIntervalSince1970: 1_105))
    #expect(rest.adjusted(by: -15).endsAt == Date(timeIntervalSince1970: 1_075))
    #expect(rest.adjusted(by: -100).endsAt == Date(timeIntervalSince1970: 1_015))
    #expect(RestState(key: key, startedAt: start, seconds: 595).adjusted(by: 15).total == 600)
    #expect(rest.adjusted(by: 15).startedAt == start)
  }

  @Test("o descanso volta do disco igual")
  func roundTrips() throws {
    let rest = RestState(key: key, startedAt: start, seconds: 75)
    let data = try JSONEncoder.henrique().encode(rest)
    #expect(try JSONDecoder.henrique().decode(RestState.self, from: data) == rest)
  }

  @Test("o relógio da barra", arguments: [(0.0, "0:00"), (5, "0:05"), (65, "1:05"), (600, "10:00"), (89.6, "1:30")])
  func clock(seconds: Double, expected: String) {
    #expect(restClock(seconds) == expected)
  }
}

// Dentro da suíte da fila porque as duas dividem a rede falsa e o disco, e
// suítes irmãs rodam em paralelo.
extension PendingSetQueueTests {
@Suite("O descanso na store")
@MainActor
struct StoreRestTests {
  init() {
    FakeNetwork.reset()
    resetLocalState()
  }

  @Test("marcar série valendo abre o descanso do exercício, que sobrevive ao app fechar")
  func startsAndPersists() async throws {
    let alarm = FakeRestAlarm()
    let store = await lojaComPainel(alarm: alarm)
    let before = Date.now
    _ = await store.record(key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
      .value
    let rest = try #require(store.rest)
    #expect(rest.key == workKey("supino-reto", 2))
    #expect(rest.total == 90)
    #expect(rest.startedAt >= before)
    #expect(alarm.scheduled == rest.endsAt)

    let relaunched = makeStore()
    #expect(relaunched.rest == rest)
  }

  @Test("desmarcar outra série não mata o descanso; desmarcar a que abriu, sim")
  func unmarkOnlyClearsItsOwnRest() async throws {
    let alarm = FakeRestAlarm()
    let store = await lojaComPainel(alarm: alarm)
    _ = await store.record(key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
      .value
    #expect(store.rest != nil)

    _ = await store.record(key: workKey("supino-reto", 1), weightKg: 42.5, reps: 9, completed: false, toFailure: true)?
      .value
    #expect(store.rest?.key == workKey("supino-reto", 2))
    #expect(alarm.cancels == 0)

    _ = await store.record(key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: false, toFailure: true)?
      .value
    #expect(store.rest == nil)
    #expect(alarm.cancels == 1)
    #expect(makeStore().rest == nil)
  }

  @Test("a última série do treino não abre descanso")
  func noRestAfterLastSet() async {
    let store = await lojaComPainel()
    _ = await store.record(key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
      .value
    _ = await store.record(key: workKey("desenvolvimento", 1), weightKg: 14, reps: 12, completed: true, toFailure: false)?
      .value
    #expect(store.rest?.key == workKey("desenvolvimento", 1))
    _ = await store.record(key: workKey("desenvolvimento", 2), weightKg: 14, reps: 12, completed: true, toFailure: false)?
      .value
    #expect(store.dashboard?.workout?.completedWorkSetCount == 4)
    #expect(store.rest == nil)
  }

  @Test("+15 s vira o descanso do exercício no aparelho")
  func adjustmentBecomesTheExerciseRest() async throws {
    let alarm = FakeRestAlarm()
    let store = await lojaComPainel(alarm: alarm)
    _ = await store.record(key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
      .value
    let started = try #require(store.rest)
    store.adjustRest(by: 15)
    #expect(store.rest?.endsAt == started.endsAt + 15)
    #expect(alarm.scheduled == started.endsAt + 15)
    #expect(store.restSeconds(for: "supino-reto") == 105)
    #expect(store.restSeconds(for: "desenvolvimento") == 90)
    #expect(makeStore().restSeconds(for: "supino-reto") == 105)

    store.endRest()
    #expect(store.rest == nil)
    #expect(alarm.scheduled == nil)
  }

  @Test("encerrar guarda a hora, para o descanso e uma série nova reabre")
  func finishAndReopen() async throws {
    let store = await lojaComPainel()
    let workout = try #require(store.dashboard?.workout)
    _ = await store.record(key: workKey("supino-reto", 2), weightKg: 42.5, reps: 8, completed: true, toFailure: true)?
      .value
    store.finishWorkout()
    let closed = try #require(store.finishedAt(workout.id, on: .today))
    #expect(store.rest == nil)
    #expect(makeStore().finishedAt(workout.id, on: .today) == closed)

    _ = await store.record(key: workKey("desenvolvimento", 1), weightKg: 14, reps: 12, completed: true, toFailure: false)?
      .value
    #expect(store.finishedAt(workout.id, on: .today) == nil)
  }

  @Test("quem estava em hoje vai para o dia novo; quem olhava outro dia fica")
  func followsTheNewDay() async {
    let store = await lojaComPainel()
    let tomorrow = CalendarDate.today.adding(days: 1)
    store.followToday(now: tomorrow)
    await esperar { store.selectedDate == tomorrow }
    #expect(store.selectedDate == tomorrow)

    let other = await lojaComPainel()
    let yesterday = CalendarDate.today.adding(days: -1)
    await other.select(date: yesterday)
    other.followToday(now: tomorrow)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(other.selectedDate == yesterday)
  }
}

}

@Suite("A sessão de treino")
struct SessionFiguresTests {
  private static func workout() throws -> WorkoutSummary {
    let data = Data(dashboardDeHoje().utf8)
    return try #require(try JSONDecoder.henrique().decode(Dashboard.self, from: data).workout)
  }

  @Test("kg até agora conta só série valendo")
  func volumeExcludesPrep() throws {
    // A fixture tem o aquecimento 1 (20 × 10) e a série 1 (42,5 × 9) feitos.
    let progress = SessionProgress(try Self.workout())
    #expect(progress.volumeKg == 382.5)
    #expect(progress.done == 1)
    #expect(progress.total == 4)
  }

  @Test("carga estranha avisa sem mexer no número")
  func weightWarnings() {
    #expect(weightWarning(25, reference: 20) == nil)
    #expect(weightWarning(250, reference: 25) == "250 kg? da última vez foi 25")
    #expect(weightWarning(450, reference: nil) == "450 kg? confere o número")
    #expect(weightWarning(1200, reference: 100) == "o limite é 1000 kg")
    #expect(weightWarning(50, reference: 0) == nil)
    #expect(weightWarning(nil, reference: 20) == nil)
  }
}
