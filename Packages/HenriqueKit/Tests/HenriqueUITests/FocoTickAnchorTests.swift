import Foundation
import HenriqueCore
import Testing

@testable import HenriqueUI

/// O total de hoje soma uma sessão fechada com 0,3 s quebrado. Ancorado no
/// segundo da corrida, o relógio virava 0,7 s depois do total completar.
struct FocoTickAnchorTests {
  let calendar = StudyFormat.calendar
  let track = FocoTrack.subject(id: "fis", name: "física", color: "#0075de")
  /// 11:13 em Fortaleza, longe da meia-noite.
  let start = Date(timeIntervalSince1970: 1_790_000_000)

  func ledger(runningSince: Date?) -> FocoLedger {
    let earlier = start.addingTimeInterval(-3600)
    return FocoLedger(
      entries: [FocoEntry(track: track, startedAt: earlier, endedAt: earlier.addingTimeInterval(10.3))],
      running: FocoRun(
        track: track, startedAt: start, stretches: [FocoStretch(start: start, end: start.addingTimeInterval(4.6))],
        runningSince: runningSince))
  }

  @Test func todayClockTicksWhenItsOwnTotalCompletesASecond() throws {
    let ledger = ledger(runningSince: start.addingTimeInterval(20))
    let shown = { (now: Date) in
      ledger.seconds(on: CalendarDate(now, in: calendar), now: now, calendar: calendar)
    }
    let anchor = try #require(ledger.tickAnchor(now: start.addingTimeInterval(42.75), showing: shown))
    for tick in [anchor.addingTimeInterval(1), anchor.addingTimeInterval(50)] {
      let total = shown(tick)
      #expect(abs(total - total.rounded()) < 1e-6)
    }
  }

  @Test func pausedRunHasNoTick() {
    #expect(ledger(runningSince: nil).tickAnchor { _ in 0 } == nil)
  }
}
