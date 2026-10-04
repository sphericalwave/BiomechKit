//
//  SorenessAttributionTests.swift
//  BiomechKitTests
//
//  Includes the case that started this: sore glutes and low back, after
//  stability-ball work yesterday and an incline pigeon two days earlier.
//

import XCTest
import AnatomyKit
@testable import BiomechKit

final class SorenessAttributionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func set(_ exercise: String, tags: [String], hoursAgo: Double, reps: Int = 12, rpe: Int = 7,
                     rpd: Int = 0, hold: Int = 0, ecc: Int = 0, position: String = "",
                     previousDaysAgo: Double? = nil, firstTime: Bool = false, n: Int = 0) -> SharedSet {
        let at = now.addingTimeInterval(-hoursAgo * 3600 + Double(n) * 120)
        return SharedSet(id: "\(exercise)-\(n)", exerciseID: exercise, exerciseName: exercise.capitalized, movementTags: tags,
                         sessionID: "s-\(Int(hoursAgo))", loggedAt: at, reps: hold > 0 ? 0 : reps, rpe: rpe, rpd: rpd,
                         weightLbs: 0, bodyweightLbs: 180, isometric: hold > 0, durationSec: hold, tempoEccentric: ecc,
                         position: position, previousDoneAt: previousDaysAgo.map { at.addingTimeInterval(-$0 * 86400) },
                         firstTime: firstTime)
    }

    func testBallBridgeOutranksPigeonAndCurls() {
        let note = SorenessNote(date: now, muscleIDs: ["gluteus_maximus"], suitJoints: ["lumbarSpine"], side: nil)
        let sets = (0..<3).map { set("ball bridge", tags: ["hip.extend"], hoursAgo: 22, reps: 15, rpe: 8, ecc: 4, previousDaysAgo: 23, n: $0) }
            + (0..<3).map { set("incline pigeon", tags: ["hip.externalRotate", "hip.flex"], hoursAgo: 46, rpe: 4, hold: 60, previousDaysAgo: 5, n: $0) }
            + (0..<3).map { set("curl", tags: ["elbow.flex"], hoursAgo: 24, n: $0) }
        let result = SorenessAttribution.rank(note, sets: sets)
        XCTAssertEqual(result.candidates.first?.exerciseID, "ball bridge")
        XCTAssertFalse(result.candidates.contains { $0.exerciseID == "curl" }, "curls load nothing in the glutes or low back")
        XCTAssertEqual(result.candidates.map(\.share).reduce(0, +), 1, accuracy: 1e-9)
        let reasons = result.candidates.first!.reasons
        XCTAssertTrue(reasons.contains(.slowLowering(seconds: 4)))
        XCTAssertTrue(reasons.contains(.returning(daysSinceLast: 23)))
        XCTAssertTrue(reasons.contains { if case let .muscles(p, _) = $0 { return p.contains("Gluteus Maximus") }; return false })
    }

    func testTimingWindow() {
        XCTAssertEqual(SorenessAttribution.kernel(3), 0)
        XCTAssertEqual(SorenessAttribution.kernel(36), 1, accuracy: 1e-9)
        XCTAssertLessThan(SorenessAttribution.kernel(96), 0.2)
        XCTAssertEqual(SorenessAttribution.kernel(130), 0)
        XCTAssertGreaterThan(SorenessAttribution.kernel(48), SorenessAttribution.kernel(16))
    }

    func testSetsAfterTheNoteOrTooRecentDontCount() {
        let note = SorenessNote(date: now, muscleIDs: ["gluteus_maximus"], suitJoints: [], side: nil)
        let result = SorenessAttribution.rank(note, sets: [set("bridge", tags: ["hip.extend"], hoursAgo: 2),
                                                           set("bridge2", tags: ["hip.extend"], hoursAgo: -10)])
        XCTAssertEqual(result.confidence, .nothing)
    }

    func testOtherSideCountsLess() {
        let note = SorenessNote(date: now, muscleIDs: ["gluteus_maximus"], suitJoints: [], side: .left)
        let left = set("left bridge", tags: ["hip.extend"], hoursAgo: 30, position: "Left")
        let right = set("right bridge", tags: ["hip.extend"], hoursAgo: 30, position: "Right")
        let result = SorenessAttribution.rank(note, sets: [left, right])
        XCTAssertEqual(result.candidates.first?.exerciseID, "left bridge")
        XCTAssertTrue(result.candidates.last!.reasons.contains(.otherSide))
    }

    func testFirstTimeRaisesAndPainFlagsStrain() {
        let note = SorenessNote(date: now, muscleIDs: ["biceps_femoris"], suitJoints: [], side: nil)
        let result = SorenessAttribution.rank(note, sets: [set("nordic", tags: ["knee.flex"], hoursAgo: 8, rpd: 7, firstTime: true)])
        let reasons = result.candidates.first?.reasons ?? []
        XCTAssertTrue(reasons.contains(.firstTime))
        XCTAssertTrue(reasons.contains(.possibleStrain(discomfort: 7)))
    }

    func testSnapshotRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "recent-sets-test.json")
        let snapshot = RecentSets(generatedAt: now, sets: [set("bridge", tags: ["hip.extend"], hoursAgo: 20)])
        try snapshot.write(to: url)
        let read = try RecentSets.read(from: url)
        XCTAssertEqual(read.sets, snapshot.sets)
    }

    func testReasonsReadPlainly() {
        XCTAssertEqual(SorenessReason.timing(hours: 22, window: .early).text, "22 h before: early in the usual soreness window")
        XCTAssertEqual(SorenessReason.timing(hours: 46, window: .peak).text, "46 h before: the usual peak for soreness")
        XCTAssertEqual(SorenessReason.muscles(prime: ["Gluteus Maximus"], assisting: ["Biceps Femoris"]).text,
                       "Gluteus Maximus: main mover; Biceps Femoris: assisting")
    }
}

extension SorenessAttributionTests {
    func testReturningWording() {
        XCTAssertEqual(SorenessReason.returning(daysSinceLast: 23).text, "First time in 23 days")
    }
}
