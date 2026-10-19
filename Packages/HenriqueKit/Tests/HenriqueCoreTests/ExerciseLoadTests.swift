import Foundation
import Testing

@testable import HenriqueCore

/// O exercício como o servidor antigo manda: as séries abertas repetem a
/// última vez, índice por índice, e o plano já pode estar com outra carga.
private func exercise(
  plan: Double, previous: [Double], rows: [Double]? = nil, done: [Int: Double] = [:],
  prepPlan: Double? = nil, previousPrep: [Double] = [], prepRows: [Double] = []
) -> DashboardExercise {
  let day = CalendarDate(iso: "2026-10-12")!
  let rows = rows ?? previous
  return DashboardExercise(
    id: "supino", name: "Supino", muscleGroup: "peito", equipment: "barra", imageUrl: nil, order: 1,
    prescription: ExercisePrescription(
      prepSets: prepRows.count, workSets: rows.count, repsMin: 6, repsMax: 10, workToFailure: false,
      startingWeightKg: plan),
    previous: previous.isEmpty ? nil : PreviousWorkSets(
      date: day, weightKg: previous.max()!, reps: previous.map { _ in 8 },
      volumeKg: previous.reduce(0) { $0 + $1 * 8 },
      sets: previous.enumerated().map { .init(index: $0.offset + 1, weightKg: $0.element, reps: 8) }),
    sets: ExerciseSets(
      prep: prepRows.enumerated().map {
        PrepSet(index: $0.offset + 1, weightKg: $0.element, reps: 10, completedAt: nil)
      },
      work: rows.enumerated().map { row in
        let index = row.offset + 1
        return WorkSet(
          index: index, weightKg: done[index] ?? row.element, reps: 8, toFailure: false,
          completedAt: done[index].map { _ in Date.now })
      }),
    note: nil, origin: .plano, prepWeightKg: prepPlan,
    previousPrep: previousPrep.isEmpty ? nil : PreviousPrepSets(
      date: day,
      sets: previousPrep.enumerated().map { .init(index: $0.offset + 1, weightKg: $0.element, reps: 10) }))
}

@Suite("A carga do exercício nas séries abertas")
struct ExerciseLoadTests {
  @Test("a carga editada no plano abre as séries com ela")
  func editedPlanMovesOpenSets() {
    let opened = exercise(plan: 60, previous: [50, 50]).applyingLoad(60)
    #expect(opened.sets.work.map(\.weightKg) == [60, 60])
  }

  @Test("uma pirâmide deslocada continua pirâmide")
  func pyramidShifts() {
    let opened = exercise(plan: 100, previous: [100, 90, 80]).applyingLoad(105)
    #expect(opened.sets.work.map(\.weightKg) == [105, 95, 85])
    #expect(opened.prescription.startingWeightKg == 105)
  }

  @Test("série marcada e série digitada sem marcar ficam como estão")
  func markedAndTypedSetsStay() {
    let opened = exercise(plan: 50, previous: [50, 50, 50], rows: [50, 50, 70], done: [1: 47.5])
      .applyingLoad(55)
    #expect(opened.sets.work.map(\.weightKg) == [47.5, 55, 70])
    #expect(opened.sets.work[0].isDone)
  }

  @Test("aplicar de novo, ou depois de outra carga, chega no mesmo lugar")
  func converges() {
    let base = exercise(
      plan: 100, previous: [100, 90, 80], previousPrep: [40, 60], prepRows: [40, 60])
    let once = base.applyingLoad(110)
    #expect(once.applyingLoad(110) == once)
    #expect(base.applyingLoad(105).applyingLoad(110) == once)
  }

  @Test("o aquecimento fixado vence a última vez; sem ele, a última vez escala com a carga")
  func warmUpFollowsTheLoad() {
    let fixed = exercise(
      plan: 40, previous: [40, 40], prepPlan: 30, previousPrep: [20, 30], prepRows: [20, 30])
    #expect(fixed.applyingLoad(40).sets.prep.map(\.weightKg) == [30, 30])

    let scaled = exercise(plan: 40, previous: [40, 40], previousPrep: [20, 30], prepRows: [20, 30])
    #expect(scaled.applyingLoad(50).sets.prep.map(\.weightKg) == [25, 37.5])
    #expect(scaled.applyingLoad(40).sets.prep.map(\.weightKg) == [20, 30])
  }
}
