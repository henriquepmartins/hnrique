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

struct WorkoutToneTests {
  private func item(_ id: String, _ weekdays: [Int], color: String? = nil) -> WeekPlanItem {
    WeekPlanItem(
      id: id, weekdays: weekdays, name: id, focus: "foco", exerciseCount: 0, exercises: [], color: color)
  }

  @Test("treino sem cor salva mantém a cor quando perde ou troca de dia")
  func toneWithoutColorIgnoresWeekdays() {
    let ids = ["pernas", "superiores", "b1f0c2a4-7e1d-4c55-9f3b-0d2a6e8c1f00"]
    for id in ids {
      let before = item(id, [1, 4]).tone
      #expect(item(id, []).tone == before)
      #expect(item(id, [3]).tone == before)
    }
  }

  @Test("cor salva vence a do id")
  func savedColorWins() {
    let hex = WorkoutTone.all[2].hex
    #expect(item("pernas", [1], color: hex).tone.hex == hex)
  }

  @Test("treinos sem cor salva nunca dividem a mesma cor, nem com a salva")
  func colorlessWorkoutsGetDistinctColors() {
    let saved = WorkoutTone.all[0].hex
    let plan = (1..<WorkoutTone.all.count).map { item("treino-\($0)", [$0 % 7]) }
      + [item("salvo", [1], color: saved)]
    let hexes = plan.withResolvedColors().map(\.tone.hex)
    #expect(Set(hexes).count == hexes.count)
  }

  @Test("a cor resolvida não muda quando o treino troca de dia")
  func resolvedColorIgnoresWeekdays() {
    let before = [item("pernas", [1]), item("superiores", [3])].withResolvedColors().map(\.color)
    let after = [item("pernas", []), item("superiores", [1, 5])].withResolvedColors().map(\.color)
    #expect(before == after)
  }
}
