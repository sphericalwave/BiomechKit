//
//  SorenessAttribution.swift
//  BiomechKit
//
//  Which recent sets most likely explain a soreness note, and why
//  (SORENESS_ATTRIBUTION_PLAN.md §2). Deterministic: every number is computed
//  here and every reason is a fact from the logs, so an AI layer can only
//  rephrase them.
//

import Foundation
import AnatomyKit

public struct SorenessNote: Sendable {
    public var date: Date
    /// Catalog muscle IDs named in the note.
    public var muscleIDs: [String]
    /// SuitKit `Joint` raw values named in the note ("lumbarSpine", "hip").
    public var suitJoints: [String]
    /// Nil for both sides or unspecified.
    public var side: BodySide?
    /// 1–10 on torque's discomfort scale; 0 = not rated.
    public var discomfort: Int

    public init(date: Date, muscleIDs: [String], suitJoints: [String], side: BodySide?, discomfort: Int = 0) {
        self.date = date; self.muscleIDs = muscleIDs; self.suitJoints = suitJoints
        self.side = side; self.discomfort = discomfort
    }
}

public struct SorenessCandidate: Identifiable, Sendable {
    public var id: String { "\(exerciseID)@\(sessionKey)" }
    public let exerciseID: String
    public let exerciseName: String
    public let sessionKey: String
    /// The latest set of this exercise in that session.
    public let lastSetAt: Date
    /// Share of all candidates' scores, 0…1.
    public let share: Double
    public let score: Double
    public let reasons: [SorenessReason]
}

public enum SorenessReason: Hashable, Sendable {
    public enum Window: String, Sendable { case early, peak, late }
    /// Hours between the last set and the note, and where that falls in the
    /// usual soreness window (early 12–24 h, peak 24–48 h, late 48–96 h).
    case timing(hours: Int, window: Window)
    /// Muscles the set loaded that are in the sore area.
    case muscles(prime: [String], assisting: [String])
    case volume(sets: Int, reps: Int, holdSeconds: Int, effort: Int?, loadLbs: Double?)
    case firstTime
    case returning(daysSinceLast: Int)
    case slowLowering(seconds: Int)
    case otherSide
    /// High discomfort during a set shortly before the note: maybe a strain, not soreness.
    case possibleStrain(discomfort: Int)

    /// Plain wording, for when no AI phrasing is available.
    public var text: String {
        switch self {
        case let .timing(h, w):
            let when = h < 48 ? "\(h) h" : "\(Int((Double(h) / 24).rounded())) days"
            return "\(when) before: \(w == .peak ? "the usual peak for soreness" : w == .early ? "early in the usual soreness window" : "late in the usual soreness window")"
        case let .muscles(p, a):
            let main = p.isEmpty ? "" : "\(Self.list(p)): main mover\(p.count > 1 ? "s" : "")"
            let help = a.isEmpty ? "" : "\(Self.list(a)): assisting"
            return [main, help].filter { !$0.isEmpty }.joined(separator: "; ")
        case let .volume(sets, reps, hold, effort, load):
            var parts = [hold > 0 ? "\(sets) × \(hold / max(1, sets)) s hold" : "\(sets) set\(sets == 1 ? "" : "s"), \(reps) reps"]
            if let effort { parts.append("effort \(effort)/10") }
            if let load { parts.append("\(Int(load)) lb") }
            return parts.joined(separator: ", ")
        case .firstTime: return "First time you've logged this exercise"
        case let .returning(d): return "First time in \(d) days"
        case let .slowLowering(s): return "Slow lowering: \(s) s"
        case .otherSide: return "Logged on the other side"
        case let .possibleStrain(d): return "Discomfort \(d)/10 during the set: could be a strain rather than soreness"
        }
    }

    private static func list(_ names: [String]) -> String {
        names.count <= 2 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

public struct SorenessAttributionResult: Sendable {
    public enum Confidence: String, Sendable { case likely, possible, unclear, nothing }
    public let candidates: [SorenessCandidate]
    public let confidence: Confidence
}

public enum SorenessAttribution {
    /// Below this, nothing logged explains the note.
    static let floor = 0.05

    public static func rank(_ note: SorenessNote, sets: [SharedSet],
                            catalog: AnatomyCatalog = .standard) -> SorenessAttributionResult {
        let area = soreWeights(note, catalog)
        guard !area.isEmpty else { return .init(candidates: [], confidence: .nothing) }

        let groups = Dictionary(grouping: sets.filter { $0.loggedAt < note.date }) {
            "\($0.exerciseID)@\($0.sessionID ?? Self.day($0.loggedAt))"
        }
        var scored: [(SorenessCandidate, Double)] = []
        for (key, group) in groups {
            guard let first = group.first, let last = group.max(by: { $0.loggedAt < $1.loggedAt }) else { continue }
            let loaded = loadedMuscles(first.movementTags, catalog)
            let match = matchScore(area, loaded)
            guard match > 0 else { continue }
            var timed = 0.0
            for set in group {
                let h = note.date.timeIntervalSince(set.loggedAt) / 3600
                timed += (kernel(h) + acute(h, set.rpd)) * dose(set)
            }
            guard timed > 0 else { continue }
            let sideFactor = sideOf(group).map { side in note.side.map { $0 == side ? 1 : 0.3 } ?? 1 } ?? 1
            let novelty = first.firstTime ? 2.0 : first.previousDoneAt.map {
                1 + (1 - exp(-first.loggedAt.timeIntervalSince($0) / 86400 / 14))
            } ?? 1
            let ecc = group.map(\.tempoEccentric).max() ?? 0
            let slow = min(1.6, 1 + 0.12 * Double(ecc))
            let score = log1p(timed / 5) * match * sideFactor * novelty * slow

            let hours = Int((note.date.timeIntervalSince(last.loggedAt) / 3600).rounded())
            var reasons: [SorenessReason] = [.timing(hours: hours, window: hours < 24 ? .early : hours <= 48 ? .peak : .late)]
            let named = loaded.filter { area[$0.key] != nil }
            let names = { (role: Muscle.Action.Role) in
                named.filter { $0.value.role == role }.sorted { (area[$0.key] ?? 0) > (area[$1.key] ?? 0) }
                    .compactMap { catalog.muscle(MuscleID($0.key))?.name }
            }
            reasons.append(.muscles(prime: names(.prime), assisting: names(.secondary)))
            let efforts = group.map(\.rpe).filter { $0 > 0 }
            let loadLbs = group.map(\.weightLbs).max() ?? 0
            reasons.append(.volume(sets: group.count, reps: group.reduce(0) { $0 + ($1.isometric ? 0 : $1.reps) },
                                   holdSeconds: group.reduce(0) { $0 + ($1.isometric ? $1.durationSec : 0) },
                                   effort: efforts.isEmpty ? nil : Int((Double(efforts.reduce(0, +)) / Double(efforts.count)).rounded()),
                                   loadLbs: loadLbs > 0 ? loadLbs : nil))
            if first.firstTime { reasons.append(.firstTime) }
            else if let prev = first.previousDoneAt {
                let days = Int(first.loggedAt.timeIntervalSince(prev) / 86400)
                if days >= 7 { reasons.append(.returning(daysSinceLast: days)) }
            }
            if ecc >= 3 { reasons.append(.slowLowering(seconds: ecc)) }
            if sideFactor < 1 { reasons.append(.otherSide) }
            if let worst = group.map(\.rpd).max(), worst >= 6, hours < 24 { reasons.append(.possibleStrain(discomfort: worst)) }

            scored.append((SorenessCandidate(exerciseID: first.exerciseID, exerciseName: first.exerciseName, sessionKey: key,
                                             lastSetAt: last.loggedAt, share: 0, score: score, reasons: reasons), score))
        }
        let total = scored.reduce(0) { $0 + $1.1 }
        let ranked = scored.filter { $0.1 >= floor }.sorted { $0.1 > $1.1 }.map { c, s in
            SorenessCandidate(exerciseID: c.exerciseID, exerciseName: c.exerciseName, sessionKey: c.sessionKey,
                              lastSetAt: c.lastSetAt, share: total > 0 ? s / total : 0, score: s, reasons: c.reasons)
        }
        guard let top = ranked.first else { return .init(candidates: [], confidence: .nothing) }
        let second = ranked.dropFirst().first?.share ?? 0
        let confidence: SorenessAttributionResult.Confidence =
            top.share >= 0.6 && top.share >= 2 * second ? .likely : top.share >= 0.35 ? .possible : .unclear
        return .init(candidates: ranked, confidence: confidence)
    }

    // MARK: Terms

    /// DOMS timing: a bell curve in log-hours peaking at 36 h — about 0.13 at
    /// 16 h, 0.6 at 24 h, 1 at 36 h, 0.77 at 48 h, 0.05 at 96 h; zero before 6 h
    /// and after 120 h.
    static func kernel(_ hours: Double) -> Double {
        guard hours >= 6, hours <= 120 else { return 0 }
        let s = 0.4, mu = log(36.0)
        return exp(-pow(log(hours) - mu, 2) / (2 * s * s))
    }

    /// A set that hurt during it can explain a note within the day.
    static func acute(_ hours: Double, _ rpd: Int) -> Double {
        guard rpd >= 6, hours >= 0, hours < 24 else { return 0 }
        return 0.5 * exp(-hours / 12)
    }

    static func dose(_ set: SharedSet) -> Double {
        let units = set.isometric ? Double(set.durationSec) / 3 : Double(set.reps)
        let effort = set.rpe > 0 ? pow(Double(set.rpe) / 10, 2) : 0.5
        let load = set.weightLbs > 0 && set.bodyweightLbs > 0 ? 1 + set.weightLbs / set.bodyweightLbs : 1
        return units * effort * load
    }

    /// Muscle → weight in the sore area: named muscles count fully; a named
    /// joint brings its soreness area's weighted muscles.
    static func soreWeights(_ note: SorenessNote, _ catalog: AnatomyCatalog) -> [String: Double] {
        var w: [String: Double] = [:]
        for id in note.muscleIDs { w[id] = 1 }
        for joint in note.suitJoints {
            for m in catalog.sorenessArea(forSuitJoint: joint)?.muscles ?? [] {
                w[m.muscle.rawValue] = max(w[m.muscle.rawValue] ?? 0, m.weight)
            }
        }
        return w
    }

    /// Muscle → its strongest role across the exercise's movements.
    static func loadedMuscles(_ tags: [String], _ catalog: AnatomyCatalog) -> [String: (role: Muscle.Action.Role, weight: Double)] {
        var out: [String: (role: Muscle.Action.Role, weight: Double)] = [:]
        for tag in tags {
            guard let dir = catalog.direction(forTorqueMovement: tag) else { continue }
            for (muscle, role) in catalog.muscles(producing: dir.id) {
                let w = role == .prime ? 1.0 : 0.5
                if (out[muscle.id.rawValue]?.weight ?? 0) < w { out[muscle.id.rawValue] = (role, w) }
            }
        }
        return out
    }

    /// How much of the sore area the exercise loaded, 0…1.
    static func matchScore(_ area: [String: Double], _ loaded: [String: (role: Muscle.Action.Role, weight: Double)]) -> Double {
        let total = area.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return area.reduce(0) { $0 + $1.value * (loaded[$1.key]?.weight ?? 0) } / total
    }

    /// The side every set of the group was on, if they agree.
    static func sideOf(_ group: [SharedSet]) -> BodySide? {
        let sides = Set(group.map { p -> BodySide? in
            let l = p.position.lowercased()
            return l.hasPrefix("left") ? .left : l.hasPrefix("right") ? .right : nil
        })
        return sides.count == 1 ? sides.first ?? nil : nil
    }

    private static func day(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}
