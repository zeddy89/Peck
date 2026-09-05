import XCTest
import CoreGraphics

final class DeliveryRunnerTests: XCTestCase {
    func testSecureInputDisablesProtectionAndStopsStreamWithoutCleanup() {
        XCTAssertFalse(KeyMonitor.protectionAvailable(tapEnabled: true, secureInput: true))
        XCTAssertFalse(KeyMonitor.protectionAvailable(tapEnabled: false, secureInput: false))
        XCTAssertTrue(KeyMonitor.protectionAvailable(tapEnabled: true, secureInput: false))
        let plan = TextProcessing.typingPlan(for: "abc", workaround: .bracketedPaste,
            stripTrailingNewline: false, appendReturn: false)
        var secureInput = false
        var received: [TypingInstruction] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { _ in secureInput = true })
        XCTAssertEqual(runner.run(plan: plan, characterDelay: 0.1, newlineDelay: 0, bracketed: true,
            targetReady: { KeyMonitor.protectionAvailable(tapEnabled: true, secureInput: secureInput) },
            execute: { received.append($0) }, progress: { _ in }, cleanup: {}), .targetChanged)
        XCTAssertEqual(received, TextProcessing.bracketedPasteMarker(open: true),
                       "No content or closing sequence may be sent after Escape protection is lost")
    }

    func testFocusLossDuringDelayStopsBeforeNextCharacter() {
        var focused = true
        var received: [TypingInstruction] = []
        var delay: TimeInterval = 0
        let runner = DeliveryRunner(cancelled: { false }, sleep: { delay += $0; focused = false })
        XCTAssertEqual(runner.run(plan: [.key(.literal("a")), .key(.literal("b"))],
            characterDelay: 10, newlineDelay: 0, bracketed: false,
            targetReady: { focused }, execute: { received.append($0) }, progress: { _ in }, cleanup: {}), .targetChanged)
        XCTAssertEqual(received, [.key(.literal("a"))])
        XCTAssertLessThanOrEqual(delay, 0.02)
    }

    func testSameApplicationDifferentWindowStopsDelivery() {
        let original = TargetIdentity(pid: 123, windowID: 1)
        var current = original
        var received: [TypingInstruction] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { _ in
            current = TargetIdentity(pid: 123, windowID: 2)
        })
        XCTAssertEqual(runner.run(plan: [.key(.literal("a")), .key(.literal("b"))],
            characterDelay: 0.1, newlineDelay: 0, bracketed: false,
            targetReady: { current == original }, execute: { received.append($0) },
            progress: { _ in }, cleanup: {}), .targetChanged)
        XCTAssertEqual(received, [.key(.literal("a"))])
    }

    func testFocusLossDuringMarkerStopsImmediatelyWithoutClosingIntoNewTarget() {
        let plan = TextProcessing.typingPlan(for: "abc", workaround: .bracketedPaste,
            stripTrailingNewline: false, appendReturn: false)
        var focused = true
        var received: [TypingInstruction] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { _ in })
        XCTAssertEqual(runner.run(plan: plan, characterDelay: 0, newlineDelay: 0, bracketed: true,
            targetReady: { focused }, execute: { received.append($0); focused = false },
            progress: { _ in }, cleanup: {}), .targetChanged)
        XCTAssertEqual(received, [.escape])
    }

    func testTransientFocusLossIsLatchedAndSuppressesBracketCleanup() {
        let plan = TextProcessing.typingPlan(for: "abc", workaround: .bracketedPaste,
            stripTrailingNewline: false, appendReturn: false)
        var queries = 0
        var received: [TypingInstruction] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { _ in })
        XCTAssertEqual(runner.run(plan: plan, characterDelay: 0, newlineDelay: 0, bracketed: true,
            targetReady: { queries += 1; return queries != 9 },
            execute: { received.append($0) }, progress: { _ in }, cleanup: {}), .targetChanged)
        XCTAssertEqual(received, TextProcessing.bracketedPasteMarker(open: true))
    }

    func testEscapeCancellationDoesNotSendBracketCleanupWhenForbidden() {
        let plan = TextProcessing.typingPlan(for: "abc", workaround: .bracketedPaste,
            stripTrailingNewline: false, appendReturn: false)
        var cancelled = false
        var received: [TypingInstruction] = []
        let runner = DeliveryRunner(cancelled: { cancelled }, sleep: { _ in })
        XCTAssertEqual(runner.run(plan: plan, characterDelay: 0, newlineDelay: 0, bracketed: true,
            permitsCleanup: { false }, execute: { received.append($0) },
            progress: { _ in cancelled = true }, cleanup: {}), .cancelled)
        XCTAssertEqual(received, TextProcessing.bracketedPasteMarker(open: true))
    }

    func testProductionEscapeHandlerSwallowsDownRepeatAndMatchingUpSynchronously() throws {
        let monitor = KeyMonitor()
        monitor.filter.begin()
        var cancelled = false
        monitor.filter.onCancel = { reason in XCTAssertEqual(reason, .escape); cancelled = true }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        XCTAssertNil(monitor.handle(type: .keyDown, event: down))
        XCTAssertTrue(cancelled, "Cancel must happen before handler returns to the event system")
        monitor.filter.end()
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(monitor.handle(type: .keyDown, event: down))
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false))
        XCTAssertNil(monitor.handle(type: .keyUp, event: up))
        XCTAssertNotNil(monitor.handle(type: .keyDown, event: down), "Idle Escape must pass after its swallowed pair ends")
    }

    func testProductionHandlerPassesSyntheticEscapeAndCancelsPhysicalInteraction() throws {
        let monitor = KeyMonitor()
        monitor.filter.begin()
        var reasons: [InputAbortFilter.Reason] = []
        monitor.filter.onCancel = { reasons.append($0) }
        let escape = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        escape.setIntegerValueField(.eventSourceUserData, value: SyntheticEventTag.magic)
        XCTAssertNotNil(monitor.handle(type: .keyDown, event: escape))
        let ordinary = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertNotNil(monitor.handle(type: .keyDown, event: ordinary))
        XCTAssertTrue(reasons.isEmpty, "Preparation must permit confirmation and focus interaction")
        monitor.filter.beginDelivery()
        XCTAssertNotNil(monitor.handle(type: .keyDown, event: ordinary))
        XCTAssertEqual(reasons, [.interaction])
        let mouse = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: .zero, mouseButton: .left))
        XCTAssertNotNil(monitor.handle(type: .leftMouseDown, event: mouse))
        XCTAssertEqual(reasons, [.interaction, .interaction])
    }

    func testProductionTapFailureCallsInterruptionSynchronously() throws {
        let monitor = KeyMonitor()
        var interrupted = 0
        monitor.onInterruption = { interrupted += 1 }
        let event = try XCTUnwrap(CGEvent(source: nil))
        XCTAssertNotNil(monitor.handle(type: .tapDisabledByTimeout, event: event))
        XCTAssertEqual(interrupted, 1)
        XCTAssertFalse(monitor.isHealthy)
        XCTAssertNotNil(monitor.handle(type: .tapDisabledByUserInput, event: event))
        XCTAssertEqual(interrupted, 2)
    }

    func testCurrentFocusStartupDoesNotRunClickSettlement() {
        var elapsed: TimeInterval = 0
        var targetChecks = 0
        let runner = DeliveryRunner(cancelled: { false }, sleep: { elapsed += $0 })
        XCTAssertEqual(runner.prepare(settleDelay: 99, focusDelay: 0.4,
            modifiersReleased: { true }, focus: nil,
            targetReady: { targetChecks += 1; return true }), .posted)
        XCTAssertGreaterThan(targetChecks, 0)
        XCTAssertGreaterThanOrEqual(elapsed, 0.4)
        XCTAssertLessThan(elapsed, 1, "Current insertion-point delivery must not run click settlement")
    }

    func testStartupWaitsForModifiersThenFocusAndRechecksAfterSettling() {
        var time: TimeInterval = 0
        var focusTime: TimeInterval?
        var targetChecks: [TimeInterval] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { time += $0 })
        XCTAssertEqual(runner.prepare(settleDelay: 0.15, focusDelay: 0.4,
            modifiersReleased: { time >= 0.06 }, focus: { focusTime = time },
            targetReady: { targetChecks.append(time); return true }), .posted)
        XCTAssertNotNil(focusTime)
        XCTAssertGreaterThanOrEqual(focusTime!, 0.29 - 0.000001)
        XCTAssertTrue(targetChecks.allSatisfy { $0 >= focusTime! })
        XCTAssertTrue(targetChecks.contains { $0 >= focusTime! + 0.48 - 0.000001 },
                      "The target must be checked again after the configured delay")
    }

    func testStartupTimeoutOrCancellationNeverClicks() {
        let runner = DeliveryRunner(cancelled: { false }, sleep: { _ in })
        XCTAssertEqual(runner.prepare(settleDelay: 0.15, focusDelay: 0.4,
            modifiersReleased: { false }, focus: { XCTFail("Must not click with held modifiers") },
            targetReady: { XCTFail("Must not inspect target yet"); return true }), .targetNotReady)
        var cancelled = false
        let cancelling = DeliveryRunner(cancelled: { cancelled }, sleep: { _ in cancelled = true })
        XCTAssertEqual(cancelling.prepare(settleDelay: 0.15, focusDelay: 0.4,
            modifiersReleased: { true }, focus: { XCTFail("Cancelled startup must not click") },
            targetReady: { true }), .cancelled)
    }

    func testStartupRejectsTargetLostDuringFocusDelay() {
        var time: TimeInterval = 0
        let runner = DeliveryRunner(cancelled: { false }, sleep: { time += $0 })
        XCTAssertEqual(runner.prepare(settleDelay: 0, focusDelay: 0.4,
            modifiersReleased: { true }, focus: {}, targetReady: { time < 0.3 }), .targetNotReady)
    }

    func testCancellationInterruptsTenSecondCharacterDelayBeforeNextKey() {
        var cancelled = false
        var slept: TimeInterval = 0
        var events: [TypingInstruction] = []
        var cleaned = false
        let runner = DeliveryRunner(cancelled: { cancelled }, sleep: {
            slept += $0
            cancelled = true
        })
        let outcome = runner.run(plan: [.key(.literal("a")), .key(.literal("b"))],
                                 characterDelay: 10, newlineDelay: 0, bracketed: false,
                                 execute: { events.append($0) }, progress: { _ in },
                                 cleanup: { cleaned = true })
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(events, [.key(.literal("a"))])
        XCTAssertLessThanOrEqual(slept, 0.02)
        XCTAssertTrue(cleaned)
    }

    func testAlreadyCancelledRunPostsNothingButStillCleansUp() {
        var events = 0
        var cleanups = 0
        let runner = DeliveryRunner(cancelled: { true }, sleep: { _ in XCTFail("Must not sleep") })
        XCTAssertEqual(runner.run(plan: [.key(.literal("a"))], characterDelay: 1,
                                  newlineDelay: 1, bracketed: false,
                                  execute: { _ in events += 1 }, progress: { _ in },
                                  cleanup: { cleanups += 1 }), .cancelled)
        XCTAssertEqual(events, 0)
        XCTAssertEqual(cleanups, 1)
    }

    func testNewlineSettlesBeforeNextCharacter() {
        var time: TimeInterval = 0
        var eventTimes: [TimeInterval] = []
        var progress: [Int] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { time += $0 })
        XCTAssertEqual(runner.run(plan: [.key(.literal("a")), .key(.returnKey), .key(.literal("b"))],
                                  characterDelay: 0.03, newlineDelay: 0.12, bracketed: false,
                                  execute: { _ in eventTimes.append(time) },
                                  progress: { progress.append($0) }, cleanup: {}), .posted)
        XCTAssertEqual(eventTimes.count, 3)
        XCTAssertEqual(eventTimes[0], 0, accuracy: 0.000001)
        XCTAssertEqual(eventTimes[1], 0.03, accuracy: 0.000001)
        XCTAssertEqual(eventTimes[2], 0.18, accuracy: 0.000001)
        XCTAssertEqual(progress, [1, 2, 3])
    }

    func testReadinessRequiresConsecutiveStableSamples() {
        var samples = 0
        var elapsed: TimeInterval = 0
        let runner = DeliveryRunner(cancelled: { false }, sleep: { elapsed += $0 })
        XCTAssertTrue(runner.awaitReady({
            samples += 1
            return samples != 3
        }))
        XCTAssertEqual(samples, 8, "False readiness must restart the stable interval")
        XCTAssertEqual(elapsed, 0.14, accuracy: 0.000001)
    }

    func testReadinessTimeoutAndCancellation() {
        var elapsed: TimeInterval = 0
        let runner = DeliveryRunner(cancelled: { false }, sleep: { elapsed += $0 })
        XCTAssertFalse(runner.awaitReady({ false }, timeout: 0.2))
        XCTAssertGreaterThanOrEqual(elapsed, 0.2)
        XCTAssertLessThan(elapsed, 0.23)
        let cancelled = DeliveryRunner(cancelled: { true }, sleep: { _ in XCTFail("Must not sleep") })
        XCTAssertFalse(cancelled.awaitReady({ XCTFail("Must not probe after cancellation"); return true }))
    }

    func testCancellationInsideOpeningMarkerFinishesItAndClosesBeforeCleanup() {
        let plan = TextProcessing.typingPlan(for: "content", workaround: .bracketedPaste,
                                             stripTrailingNewline: false, appendReturn: false)
        var events: [TypingInstruction] = []
        var cancelled = false
        var countAtCleanup = 0
        let runner = DeliveryRunner(cancelled: { cancelled }, sleep: { _ in })
        XCTAssertEqual(runner.run(plan: plan, characterDelay: 0, newlineDelay: 0, bracketed: true,
                                  execute: { events.append($0); cancelled = true },
                                  progress: { _ in }, cleanup: { countAtCleanup = events.count }), .cancelled)
        let markers = TextProcessing.bracketedPasteMarker(open: true)
            + TextProcessing.bracketedPasteMarker(open: false)
        XCTAssertEqual(events, markers)
        XCTAssertEqual(countAtCleanup, markers.count)
    }

    func testCompletedBracketedPasteClosesExactlyOnceBeforeAppendedReturn() {
        let plan = TextProcessing.typingPlan(for: "x", workaround: .bracketedPaste,
                                             stripTrailingNewline: false, appendReturn: true)
        var events: [TypingInstruction] = []
        let runner = DeliveryRunner(cancelled: { false }, sleep: { _ in })
        XCTAssertEqual(runner.run(plan: plan, characterDelay: 0, newlineDelay: 0, bracketed: true,
                                  execute: { events.append($0) }, progress: { _ in }, cleanup: {}), .posted)
        XCTAssertEqual(events, plan)
        XCTAssertEqual(events.last, .key(.returnKey))
    }

    func testInterruptWaitsForBalancedStrokeAndCleanupOnProductionQueue() {
        let delivery = DeliveryQueue()
        let token = delivery.begin()!
        XCTAssertNil(delivery.begin(), "An active paste must exclude another paste")
        let pressed = expectation(description: "Pressed key")
        let completed = expectation(description: "Interrupt delivered")
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var events: [String] = []
        func record(_ value: String) { lock.lock(); events.append(value); lock.unlock() }
        delivery.submit {
            let runner = DeliveryRunner(cancelled: { delivery.isCancelled(token) })
            _ = runner.run(plan: [.key(.literal("a")), .key(.literal("b"))],
                           characterDelay: 10, newlineDelay: 0, bracketed: false,
                           execute: { _ in
                record("down")
                pressed.fulfill()
                if release.wait(timeout: .now() + 2) != .success { XCTFail("Release timeout") }
                record("up")
            }, progress: { _ in }, cleanup: { record("cleanup") })
            delivery.finish()
        }
        wait(for: [pressed], timeout: 2)
        delivery.interrupt({ _ in record("interrupt") }, completion: { completed.fulfill() })
        XCTAssertNil(delivery.begin(), "Queued special keys must also exclude a new paste")
        release.signal()
        wait(for: [completed], timeout: 2)
        lock.lock(); let recorded = events; lock.unlock()
        XCTAssertEqual(recorded, ["down", "up", "cleanup", "interrupt"])
        XCTAssertFalse(delivery.isTyping)
        let next = delivery.begin()!
        XCTAssertFalse(delivery.isCancelled(next), "Old cancellation must not poison next paste")
        delivery.finish()
    }

    func testCancelWhileSpecialKeyQueuedPreventsItsDelivery() {
        let delivery = DeliveryQueue()
        let blocked = DispatchSemaphore(value: 0)
        let completed = expectation(description: "Cancelled special completed")
        delivery.submit { _ = blocked.wait(timeout: .now() + 2) }
        delivery.interrupt({ cancelled in
            XCTAssertTrue(cancelled(), "A cancel before a queued chord runs must reach the chord")
        }, completion: { completed.fulfill() })
        XCTAssertTrue(delivery.isTyping)
        delivery.cancel()
        blocked.signal()
        wait(for: [completed], timeout: 2)
        XCTAssertFalse(delivery.isTyping)
    }

    func testSafetyCountsFinalPlanReturnsAndUnmappedLiterals() {
        let plan = TextProcessing.typingPlan(for: "a\n🙂\n", workaround: .none,
                                             stripTrailingNewline: true, appendReturn: true)
        XCTAssertEqual(PasteSafety.returnCount(in: plan), 2)
        XCTAssertEqual(PasteSafety.unsupportedCount(in: plan, maps: { $0 == "a" }), 1)
    }

    func testStrictPreflightRequiresLayoutEvenWithoutLiterals() {
        XCTAssertFalse(PasteSafety.passesStrictPreflight(plan: [.key(.returnKey)],
            mappingAvailable: false, maps: { _ in XCTFail("Missing layout must fail immediately"); return true }))
        XCTAssertFalse(PasteSafety.passesStrictPreflight(plan: [.key(.literal("a"))],
            mappingAvailable: false, maps: { _ in true }))
        XCTAssertTrue(PasteSafety.passesStrictPreflight(plan: [.key(.literal("a")), .key(.returnKey)],
            mappingAvailable: true, maps: { $0 == "a" }))
        XCTAssertFalse(PasteSafety.passesStrictPreflight(plan: [.key(.literal("🙂"))],
            mappingAvailable: true, maps: { _ in false }))
    }

    func testFixtureComparisonDetectsMissingFirstCharacterAndChangedContent() {
        XCTAssertTrue(TypingFixture.comparison(received: TypingFixture.text).hasPrefix("Exact match:"))
        XCTAssertTrue(TypingFixture.comparison(received: String(TypingFixture.text.dropFirst()))
            .contains("line 1, column 3"))
        XCTAssertTrue(TypingFixture.comparison(received: TypingFixture.text + "\n").hasPrefix("Mismatch"))
        XCTAssertTrue(TypingFixture.comparison(received: TypingFixture.text.replacingOccurrences(of: "aaa", with: "aáa"))
            .contains("line 1, column 2"))
    }
}
