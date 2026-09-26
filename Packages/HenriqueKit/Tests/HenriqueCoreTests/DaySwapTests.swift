import Foundation
import Testing

@testable import HenriqueCore

@Suite("Troca de treino do dia")
struct DaySwapTests {
  @Test("a semana de treino começa na segunda, e o domingo fecha a anterior")
  func trainingWeekStart() {
    let monday = CalendarDate(year: 2026, month: 9, day: 21)!
    #expect(CalendarDate(year: 2026, month: 9, day: 23)!.trainingWeekStart() == monday)
    #expect(monday.trainingWeekStart() == monday)
    #expect(CalendarDate(year: 2026, month: 9, day: 27)!.trainingWeekStart() == monday)
    #expect(CalendarDate(year: 2026, month: 9, day: 20)!.trainingWeekStart()
      == CalendarDate(year: 2026, month: 9, day: 14)!)
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return calendar
  }

  // Semana de 14 (segunda) a 20 (domingo) de setembro de 2026.
  private static let peito = item("peito", [1])
  private static let costas = item("costas", [2])
  private static let pernas = item("pernas", [3])
  private static let ombro = item("ombro", [])
  private static let plan = [peito, costas, pernas, ombro]

  private static func item(_ id: String, _ weekdays: [Int]) -> WeekPlanItem {
    WeekPlanItem(
      id: id, weekdays: weekdays, name: id, focus: "", exerciseCount: 0, exercises: [])
  }

  private static func day(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

  private func schedule(
    _ plan: [WeekPlanItem] = Self.plan, swaps: [(String, String)] = []
  ) -> PlanSchedule {
    PlanSchedule(
      plan: plan, swaps: swaps.map { DaySwap(date: Self.day($0.0), workoutTemplateId: $0.1) },
      calendar: calendar)
  }

  private func missed(
    _ schedule: PlanSchedule, today: String, done: [String: Int] = [:]
  ) -> [MissedWorkout] {
    schedule.missedWorkouts(
      today: Self.day(today),
      sessions: done.map { WeeklyWorkoutSessions(workoutTemplateId: $0.key, count: $0.value) })
  }

  @Test("sem troca, o dia segue o plano; com troca, vale o treino trocado")
  func workoutOnDate() {
    let plain = schedule()
    #expect(plain.workout(on: Self.day("2026-09-16"))?.id == "pernas")
    #expect(plain.workout(on: Self.day("2026-09-20")) == nil)

    let swapped = schedule(swaps: [("2026-09-16", "costas"), ("2026-09-20", "ombro")])
    #expect(swapped.workout(on: Self.day("2026-09-16"))?.id == "costas")
    #expect(swapped.weekdayWorkout(on: Self.day("2026-09-16"))?.id == "pernas")
    #expect(swapped.isSwapped(Self.day("2026-09-16")))
    #expect(swapped.workout(on: Self.day("2026-09-20"))?.id == "ombro")
    #expect(swapped.workout(on: Self.day("2026-09-23"))?.id == "pernas")
    #expect(!swapped.isSwapped(Self.day("2026-09-23")))
  }

  @Test("troca para um treino que saiu do plano cai no dia da semana")
  func swapToMissingWorkout() {
    let swapped = schedule(swaps: [("2026-09-16", "apagado")])
    #expect(swapped.workout(on: Self.day("2026-09-16"))?.id == "pernas")
  }

  @Test("o que não saiu de segunda a ontem, do dia perdido mais recente primeiro")
  func missedOrderedByLastMissedDay() {
    #expect(
      missed(schedule(), today: "2026-09-16") == [
        MissedWorkout(workout: Self.costas, lastMissed: Self.day("2026-09-15")),
        MissedWorkout(workout: Self.peito, lastMissed: Self.day("2026-09-14")),
      ])
  }

  @Test("treino feito mais tarde na semana não está atrasado")
  func completedLaterIsNotMissed() {
    #expect(
      missed(schedule(), today: "2026-09-17", done: ["costas": 1, "pernas": 1]) == [
        MissedWorkout(workout: Self.peito, lastMissed: Self.day("2026-09-14"))
      ])
  }

  @Test("o treino de hoje não entra como atrasado, mesmo perdido antes")
  func todaysWorkoutIsNotMissed() {
    let twice = [Self.item("pernas", [1, 3]), Self.costas]
    #expect(
      missed(schedule(twice), today: "2026-09-16") == [
        MissedWorkout(workout: Self.costas, lastMissed: Self.day("2026-09-15"))
      ])

    let swappedToday = schedule(swaps: [("2026-09-16", "costas")])
    #expect(
      missed(swappedToday, today: "2026-09-16") == [
        MissedWorkout(workout: Self.peito, lastMissed: Self.day("2026-09-14"))
      ])
  }

  @Test("troca num dia passado muda o que era previsto nele")
  func pastSwapChangesWhatWasPlanned() {
    let swapped = schedule(swaps: [("2026-09-15", "peito")])
    #expect(
      missed(swapped, today: "2026-09-16", done: ["peito": 1]) == [
        MissedWorkout(workout: Self.peito, lastMissed: Self.day("2026-09-15"))
      ])
  }

  @Test("a semana começa na segunda: o domingo fecha a semana, não abre")
  func weekStartsOnMonday() {
    let sunday = Self.item("domingo", [0])
    let saturday = Self.item("sabado", [6])
    #expect(
      missed(schedule([Self.peito, sunday]), today: "2026-09-14").isEmpty,
      "segunda esquece o domingo da semana anterior")
    #expect(
      missed(schedule([Self.peito, saturday, sunday]), today: "2026-09-20") == [
        MissedWorkout(workout: saturday, lastMissed: Self.day("2026-09-19")),
        MissedWorkout(workout: Self.peito, lastMissed: Self.day("2026-09-14")),
      ])
  }

  @Test("por presença, treino começado e não fechado já não está atrasado")
  func attendanceCountsPartialWorkouts() {
    let attendance = [
      AttendanceDay(date: Self.day("2026-09-13"), workSets: 5, completed: true, workoutTemplateIds: ["peito"]),
      AttendanceDay(date: Self.day("2026-09-15"), workSets: 1, completed: false, workoutTemplateIds: ["costas"]),
      AttendanceDay(date: Self.day("2026-09-16"), workSets: 0, completed: false, workoutTemplateIds: ["pernas"]),
    ]
    #expect(
      schedule().missedWorkouts(today: Self.day("2026-09-17"), attendance: attendance) == [
        MissedWorkout(workout: Self.pernas, lastMissed: Self.day("2026-09-16")),
        MissedWorkout(workout: Self.peito, lastMissed: Self.day("2026-09-14")),
      ])
  }
}
