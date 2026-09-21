import SwiftUI
import Testing

@testable import HenriqueUI

@MainActor
struct PlanMarkerMaskTests {
  private let rect = CGRect(x: 0, y: 0, width: 44, height: 44)

  @Test func startsEmptyAndFinishesEveryDay() {
    for day in 1...31 {
      #expect(PlanMarkerMask(progress: 0, day: day).path(in: rect).isEmpty)
      let final = PlanMarkerMask(progress: 1, day: day).path(in: rect)
      #expect(final.boundingRect == rect)
    }
  }

  @Test func paintCoversTheCellBeforeRemovingTheMask() {
    for day in 1...31 {
      let delay = Double(day - 1) / 30 * 0.64
      let almostDone = PlanMarkerMask(progress: delay + 0.36 * 0.999, day: day).path(in: rect)
      for x in stride(from: 1.0, through: 43.0, by: 3) {
        for y in stride(from: 1.0, through: 43.0, by: 3) {
          #expect(almostDone.contains(CGPoint(x: x, y: y)))
        }
      }
    }
  }

  @Test func laterDaysWaitForTheirTurn() {
    #expect(!PlanMarkerMask(progress: 0.2, day: 1).path(in: rect).isEmpty)
    #expect(PlanMarkerMask(progress: 0.2, day: 31).path(in: rect).isEmpty)
  }
}
