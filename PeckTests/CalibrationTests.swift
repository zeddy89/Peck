import XCTest

final class CalibrationTests: XCTestCase {
    private func model(_ target: Calibration.Target = .local) throws -> Calibration {
        try Calibration(candidates: [15, 10, 5, 2], target: target, originalDelay: 40)
    }
    private func record(_ model: inout Calibration, delay: Int, exact: Bool = true,
                        revision: Int = 0, synthetic: Bool = true) throws {
        try model.begin(delay: delay, revision: revision)
        model.runStarted()
        model.runFinished(success: true)
        try model.record(exact: exact, revision: revision + 1, syntheticOnly: synthetic)
    }
    func testThreeDistinctTrialsRequired() throws {
        var subject = try model()
        try record(&subject, delay: 15)
        XCTAssertNil(subject.recommendedDelay)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 2, syntheticOnly: true))
        try record(&subject, delay: 15, revision: 3)
        XCTAssertNil(subject.recommendedDelay)
        try record(&subject, delay: 15, revision: 5)
        XCTAssertEqual(subject.recommendedDelay, 15)
        XCTAssertEqual(subject.scores[15]?.matches, 3)
    }
    func testFasterCandidateNeedsItsOwnThreeMatches() throws {
        var subject = try model()
        for revision in 0..<3 { try record(&subject, delay: 15, revision: revision * 2) }
        for revision in 0..<2 { try record(&subject, delay: 5, revision: 10 + revision * 2) }
        XCTAssertEqual(subject.recommendedDelay, 15)
        try record(&subject, delay: 5, revision: 14)
        XCTAssertEqual(subject.recommendedDelay, 5)
    }
    func testMismatchPermanentlyInvalidatesSpeedAndRecommendsSlowerQualifiedRate() throws {
        var subject = try model()
        for delay in [15, 5, 2] {
            for _ in 0..<3 { try record(&subject, delay: delay) }
        }
        XCTAssertEqual(subject.recommendedDelay, 2)
        try record(&subject, delay: 2, exact: false)
        XCTAssertEqual(subject.recommendedDelay, 5)
        for _ in 0..<3 { try record(&subject, delay: 2) }
        XCTAssertEqual(subject.recommendedDelay, 5)
        XCTAssertEqual(subject.scores[2]?.mismatches, 1)
        try record(&subject, delay: 5, exact: false)
        XCTAssertEqual(subject.recommendedDelay, 15)
    }
    func testFailingSlowerSpeedInvalidatesFasterRecommendation() throws {
        var subject = try model()
        for _ in 0..<3 { try record(&subject, delay: 2) }
        try record(&subject, delay: 15, exact: false)
        XCTAssertNil(subject.recommendedDelay)
    }
    func testNoRunOrIncompleteRunCannotPass() throws {
        var subject = try model()
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
        try subject.begin(delay: 15, revision: 0)
        subject.runFinished(success: true)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
        subject.runStarted()
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
        XCTAssertTrue(subject.scores.isEmpty)
    }
    func testCancelledRunCannotBeChangedToSuccess() throws {
        var subject = try model()
        try subject.begin(delay: 15, revision: 0)
        subject.runStarted()
        subject.runFinished(success: false)
        subject.runFinished(success: true)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
        subject.cancelTrial()
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
        XCTAssertTrue(subject.scores.isEmpty)
    }
    func testMultipleRunsWithoutNewTrialCannotPass() throws {
        var subject = try model()
        try subject.begin(delay: 15, revision: 0)
        subject.runStarted()
        subject.runFinished(success: true)
        subject.runStarted()
        subject.runFinished(success: true)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
    }
    func testChangedRunConfigurationCannotQualifyAfterSettingsAreReverted() throws {
        var subject = try model()
        try subject.begin(delay: 15, revision: 0)
        subject.runStarted(configurationMatches: false)
        subject.runFinished(success: true)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: true))
        XCTAssertTrue(subject.scores.isEmpty)
    }
    func testQualifiedRecommendationCannotTransferToChangedConfiguration() throws {
        var subject = try model()
        for _ in 0..<3 { try record(&subject, delay: 5) }
        XCTAssertEqual(subject.recommendation(configurationMatches: true), 5)
        XCTAssertNil(subject.recommendation(configurationMatches: false))
    }
    func testStaleBufferCannotQualify() throws {
        var subject = try model()
        try subject.begin(delay: 15, revision: 7)
        subject.runStarted()
        subject.runFinished(success: true)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 7, syntheticOnly: true))
        XCTAssertTrue(subject.scores.isEmpty)
    }
    func testCompletedRunReceivingNothingCountsAsMismatchOnlyOnce() throws {
        var subject = try model()
        try subject.begin(delay: 2, revision: 7)
        subject.runStarted()
        subject.runFinished(success: true)
        try subject.record(exact: false, revision: 7, syntheticOnly: true)
        XCTAssertEqual(subject.scores[2]?.mismatches, 1)
        XCTAssertThrowsError(try subject.record(exact: false, revision: 7, syntheticOnly: true))
    }
    func testLocalManualSampleRejectedAndConsumed() throws {
        var subject = try model()
        try subject.begin(delay: 15, revision: 0)
        subject.runStarted()
        subject.runFinished(success: true)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: false))
        XCTAssertThrowsError(try subject.record(exact: true, revision: 2, syntheticOnly: true))
        XCTAssertTrue(subject.scores.isEmpty)
    }
    func testRemoteRequiresRunAndExplicitFreshReceiptButAllowsImportedText() throws {
        var subject = try model(.remote)
        try subject.begin(delay: 15, revision: 0)
        XCTAssertThrowsError(try subject.record(exact: true, revision: 1, syntheticOnly: false))
        subject.runStarted()
        subject.runFinished(success: true)
        try subject.record(exact: true, revision: 1, syntheticOnly: false)
        XCTAssertEqual(subject.scores[15]?.matches, 1)
        XCTAssertEqual(subject.target, .remote)
    }
    func testRestorationOnlyChangesOurLastAppliedDelay() throws {
        var subject = try model()
        XCTAssertNil(subject.restorationDelay(current: 40))
        try subject.begin(delay: 2, revision: 0)
        XCTAssertEqual(subject.restorationDelay(current: 2), 40)
        XCTAssertNil(subject.restorationDelay(current: 10), "Preserve a separate settings edit")
    }
    func testInvalidCandidatesRejectedAndOrderNormalized() throws {
        for candidates in [[], [2, 2], [-1], [10001], Array(0...12)] {
            XCTAssertThrowsError(try Calibration(candidates: candidates, target: .local, originalDelay: 15))
        }
        XCTAssertEqual(try Calibration(candidates: [2, 15, 5], target: .local, originalDelay: 15).candidates, [15, 5, 2])
        var subject = try model()
        XCTAssertThrowsError(try subject.begin(delay: 9, revision: 0))
    }
}
