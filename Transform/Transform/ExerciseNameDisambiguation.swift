import Foundation

/// Renames that make an exercise name say what you actually pick up.
///
/// WHY THIS EXISTS
/// ---------------
/// Names like "Hammer Curl" and "Skull Crusher" do not tell you whether to reach for
/// dumbbells, an EZ-bar, or a cable — and the answer changes the load, the log, and the
/// progression. "Leg Curl" was worse than ambiguous: it sat in the catalog beside "Seated Leg
/// Curl" and "Lying Leg Curl", so the bare name was undefined against its own siblings.
///
/// WHY IT IS A MAP AND NOT JUST AN EDIT
/// ------------------------------------
/// `canonicalLookupKey` is derived from the exercise NAME — it stems each token, drops a small
/// stop-word list that does NOT include equipment words, and sorts what remains. So
/// "Hammer Curl" keys as `curl hammer` and "Dumbbell Hammer Curl" keys as
/// `curl dumbbell hammer`. Renaming the catalog alone would leave every previously logged set
/// under the old key: the history would still be on the device and the app would never find it
/// again. That is INC-2 — the incident that silently erased the owner's logged weights — with
/// a different trigger.
///
/// This map is therefore the single source of truth for three things that must never drift:
///
/// 1. the catalog's canonical names (what new programs generate),
/// 2. the alias table (so a model still emitting the old name resolves forward),
/// 3. the startup re-keying migration (so records ALREADY on the device follow the rename).
///
/// The migration works because `normalizePerformanceLogs` re-derives the key from the stored
/// name every launch. Rewrite the name and the key follows by itself, and
/// `normalizeAndConsolidate` merges the renamed record with any history already under the new
/// name. Existing data self-heals on next launch rather than needing a bespoke migration.
///
/// ADDING TO THIS MAP
/// ------------------
/// Only add a rename when equipment genuinely changes what the lifter picks up. Names that are
/// unambiguous by convention are deliberately absent — "Back Squat", "Leg Press", "Lat
/// Pulldown", "Chin-Up" need no help, and over-qualifying every row makes the day screen
/// harder to scan, not easier. A new entry must never collide with an existing catalog name.
enum ExerciseNameDisambiguation {

    /// Old (ambiguous) name → new (explicit) name.
    ///
    /// Keys are matched case- and whitespace-insensitively via `resolved(_:)`, so plural or
    /// differently-cased variants coming from the model still land correctly.
    static let renames: [String: String] = [
        // Arms — the pair the owner reported, plus the rest of the same class.
        "Hammer Curl": "Dumbbell Hammer Curl",
        "Skull Crusher": "EZ-Bar Skull Crusher",
        "Concentration Curl": "Dumbbell Concentration Curl",
        "Spider Curl": "Dumbbell Spider Curl",
        "Preacher Curl": "EZ-Bar Preacher Curl",
        "JM Press": "EZ-Bar JM Press",
        "Close-Grip Bench Press": "Close-Grip Barbell Bench Press",

        // Shoulders / back.
        "Arnold Press": "Dumbbell Arnold Press",
        "Face Pull": "Cable Face Pull",
        "Face Pull with External Rotation": "Cable Face Pull with External Rotation",
        "Meadows Row": "Landmine Meadows Row",

        // Legs. "Leg Curl" and "Leg Extension" are machine movements whose bare names sat
        // beside more specific siblings in the same catalog.
        "Leg Curl": "Machine Leg Curl",
        "Leg Extension": "Machine Leg Extension",
        "Good Morning": "Barbell Good Morning",
        "Romanian Deadlift": "Barbell Romanian Deadlift",
        "Single-Leg Romanian Deadlift": "Dumbbell Single-Leg Romanian Deadlift",
        "Stiff-Leg Deadlift": "Barbell Stiff-Leg Deadlift",
        "Sumo Deadlift": "Barbell Sumo Deadlift",
        "Hip Thrust": "Barbell Hip Thrust",
        "Reverse Lunge": "Dumbbell Reverse Lunge",
        "Walking Lunge": "Dumbbell Walking Lunge",
        "Bulgarian Split Squat": "Dumbbell Bulgarian Split Squat",

        // Core / carries.
        "Pallof Press": "Cable Pallof Press",
        "Farmer's Walk": "Dumbbell Farmer's Walk",
        "Suitcase Carry": "Dumbbell Suitcase Carry"
    ]

    /// Case- and whitespace-insensitive lookup table, built once.
    private static let normalizedRenames: [String: String] = {
        var table: [String: String] = [:]
        for (old, new) in renames {
            table[normalizedKey(old)] = new
        }
        return table
    }()

    /// The explicit name for `name`, or `name` unchanged when it needs no disambiguation.
    ///
    /// Idempotent: passing an already-renamed name returns it untouched, which matters because
    /// the startup migration runs on every launch and must not keep rewriting records.
    static func resolved(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }
        return normalizedRenames[normalizedKey(trimmed)] ?? trimmed
    }

    /// True when `name` is one this map rewrites. Used by tests and diagnostics.
    static func needsRename(_ name: String) -> Bool {
        resolved(name) != name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
