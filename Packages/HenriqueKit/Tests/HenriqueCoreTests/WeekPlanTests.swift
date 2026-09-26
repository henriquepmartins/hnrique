import Testing

@testable import HenriqueCore

@Suite("Um treino em vários dias")
struct WeekPlanTests {
  static func item(_ id: String, _ weekdays: [Int]) -> WeekPlanItem {
    WeekPlanItem(
      id: id, weekdays: weekdays, name: id, focus: "foco", exerciseCount: 0, exercises: [])
  }

  @Test("iniciar vai para o dia mais perto, contando hoje", arguments: [
    (today: 1, expected: 1),
    (today: 2, expected: 4),
    (today: 4, expected: 4),
    (today: 5, expected: 1),
    (today: 0, expected: 1),
  ])
  func nextWeekday(today: Int, expected: Int) {
    #expect(Self.item("Superiores", [1, 4]).nextWeekday(from: today) == expected)
  }

  @Test("treino sem dia continua no plano e não tem próximo dia")
  func unscheduledWorkout() throws {
    let item = try ContractTests.planItem(
      """
      {"id": "tpl-1", "weekdays": [], "name": "Superiores", "focus": "peito",
       "exerciseCount": 0, "exercises": [], "estimatedMinutes": 55}
      """)
    #expect(item.weekdays.isEmpty)
    #expect(item.nextWeekday(from: 2) == nil)
    #expect(WeekdayOwners(plan: [item], excluding: nil).handoffs(to: [1, 2]).isEmpty)
  }

  @Test("sábado dá a volta para o domingo do mesmo treino")
  func nextWeekdayWrapsAroundTheWeek() {
    #expect(Self.item("Pernas", [0, 3]).nextWeekday(from: 6) == 0)
  }

  @Test("marcar dias de outros treinos diz quais saem e quem fica sem dia")
  func handoffsNameWhatMoves() {
    let plan = [Self.item("Superiores", [1, 4]), Self.item("Pernas", [2])]
    let owners = WeekdayOwners(plan: plan, excluding: nil)
    #expect(
      owners.handoffs(to: [2, 4, 6]) == [
        WeekdayHandoff(workoutName: "Pernas", weekdays: [2], becomesUnscheduled: true),
        WeekdayHandoff(workoutName: "Superiores", weekdays: [4], becomesUnscheduled: false),
      ])
  }

  @Test("o treino editado não tira dia de si mesmo")
  func editedWorkoutIsNotAnOwner() {
    let plan = [Self.item("Superiores", [1, 4]), Self.item("Pernas", [2])]
    let owners = WeekdayOwners(plan: plan, excluding: "Superiores")
    #expect(owners[1] == nil)
    #expect(owners[2]?.id == "Pernas")
    #expect(
      owners.handoffs(to: [1, 2, 4]) == [
        WeekdayHandoff(workoutName: "Pernas", weekdays: [2], becomesUnscheduled: true)
      ])
  }
}
