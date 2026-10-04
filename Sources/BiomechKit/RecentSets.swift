//
//  RecentSets.swift
//  BiomechKit
//
//  The sets torque shares with suit: the last 8 days, written by torque to the
//  shared App Group and only read by suit. On device only; nothing syncs.
//

import Foundation

public struct RecentSets: Codable, Sendable {
    public static let appGroupID = "group.com.sphericalwave.fitwrench.suit"
    public static let fileName = "recent-sets.json"
    public static let window: TimeInterval = 8 * 24 * 3600

    public var version = 1
    public var generatedAt: Date
    public var sets: [SharedSet]

    public init(generatedAt: Date, sets: [SharedSet]) {
        self.generatedAt = generatedAt
        self.sets = sets
    }

    public static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: fileName)
    }

    /// Written atomically, so a reader never sees half a file.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> RecentSets {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecentSets.self, from: Data(contentsOf: url))
    }
}

/// One logged set, in the fields soreness attribution uses.
public struct SharedSet: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var exerciseID: String
    public var exerciseName: String
    /// torque `Movement` raw values ("hip.extend"), resolved through AnatomyKit.
    public var movementTags: [String]
    public var sessionID: String?
    public var loggedAt: Date
    public var reps: Int
    /// Effort 1–10; 0 = not rated.
    public var rpe: Int
    /// Discomfort 1–10; 0 = not rated.
    public var rpd: Int
    public var weightLbs: Double
    public var bodyweightLbs: Double
    public var isometric: Bool
    public var durationSec: Int
    /// Seconds spent lowering.
    public var tempoEccentric: Int
    /// "Right", "Left", "Right index" …; "" when the set has no side.
    public var position: String
    /// When this exercise was last done before this set's session; nil if never or unknown.
    public var previousDoneAt: Date?
    /// True when torque has no earlier log of this exercise at all.
    public var firstTime: Bool

    public init(id: String, exerciseID: String, exerciseName: String, movementTags: [String], sessionID: String?,
                loggedAt: Date, reps: Int, rpe: Int, rpd: Int, weightLbs: Double, bodyweightLbs: Double,
                isometric: Bool, durationSec: Int, tempoEccentric: Int, position: String,
                previousDoneAt: Date?, firstTime: Bool) {
        self.id = id; self.exerciseID = exerciseID; self.exerciseName = exerciseName
        self.movementTags = movementTags; self.sessionID = sessionID; self.loggedAt = loggedAt
        self.reps = reps; self.rpe = rpe; self.rpd = rpd; self.weightLbs = weightLbs
        self.bodyweightLbs = bodyweightLbs; self.isometric = isometric; self.durationSec = durationSec
        self.tempoEccentric = tempoEccentric; self.position = position
        self.previousDoneAt = previousDoneAt; self.firstTime = firstTime
    }
}
