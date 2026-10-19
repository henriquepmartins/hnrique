import Testing

@testable import HenriqueCore
@testable import HenriqueUI

struct WeekPlanOrderTests {
  private func item(_ id: String, _ weekdays: [Int]) -> WeekPlanItem {
    WeekPlanItem(id: id, weekdays: weekdays, name: id, focus: "foco", exerciseCount: 0, exercises: [])
  }

  @Test("as pastas seguem a semana a partir da segunda, e as sem dia vão para o fim")
  func ordersByFirstTrainingDay() {
    let plan = [
      item("sem dia", []), item("domingo", [0]), item("quarta", [3]),
      item("segunda e sexta", [5, 1]), item("outro sem dia", []),
    ]
    let ordered = plan.inTrainingWeekOrder(firstWeekday: 2).map(\.id)
    #expect(ordered == ["segunda e sexta", "quarta", "domingo", "sem dia", "outro sem dia"])
  }
}
