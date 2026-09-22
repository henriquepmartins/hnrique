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

  @Test func returningToPlanDrawsAgainAfterCompletion() {
    var playback = PlanMarkerPlayback()
    let first = Date(timeIntervalSinceReferenceDate: 1_000)
    playback.start(at: first)
    playback.finish()
    #expect(playback.progress(at: first.addingTimeInterval(2)) == 1)

    playback.reset()
    let second = first.addingTimeInterval(10)
    #expect(playback.progress(at: second) == 0)
    playback.start(at: second)
    let progress = playback.progress(at: second.addingTimeInterval(0.12))
    let mask = PlanMarkerMask(progress: progress, day: 1).path(in: rect)
    #expect(playback.isDrawing)
    #expect(mask.contains(CGPoint(x: 22, y: 3)))
    #expect(!mask.contains(CGPoint(x: 22, y: 41)))
  }

  @Test func delayedDataStartsANewDrawingInsteadOfRevealingTheWholeCell() {
    var playback = PlanMarkerPlayback()
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    playback.start(at: start)
    playback.finish()
    let arrival = start.addingTimeInterval(5)
    playback.start(at: arrival)
    #expect(playback.progress(at: arrival) == 0)
    #expect(playback.progress(at: arrival.addingTimeInterval(0.5)) < 1)
    #expect(playback.progress(at: arrival.addingTimeInterval(1.2)) == 1)
  }

  @Test func interruptedEntranceCanStartAgain() {
    var playback = PlanMarkerPlayback()
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    playback.start(at: start)
    playback.finish()
    #expect(!playback.isDrawing)
    playback.reset()
    #expect(playback.progress(at: start) == 0)
    playback.start(at: start.addingTimeInterval(0.2))
    #expect(playback.isDrawing)
    #expect(playback.progress(at: start.addingTimeInterval(0.2)) == 0)
  }
}
