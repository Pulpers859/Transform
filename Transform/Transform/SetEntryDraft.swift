import Foundation

/// UI-only draft. History may suggest a load; only the lifter supplies performed reps.
struct SetEntryDraft: Equatable {
    enum RowState { case saved, entry, idle }

    static func rowState(hasSavedSet: Bool, isActive: Bool, isEditing: Bool) -> RowState {
        if hasSavedSet && (!isActive || !isEditing) { return .saved }
        return isActive ? .entry : .idle
    }

    var weight = ""
    var reps = ""
    var rir = ""

    init(suggestedWeight: Double? = nil) {
        if let load = suggestedWeight, load.isFinite, load >= 0 {
            weight = load <= 1 ? "BW" : (load.rounded() == load ? String(format: "%.0f", load) : String(load))
        }
    }

    var parsedWeight: Double? {
        let value = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.caseInsensitiveCompare("BW") == .orderedSame { return 0 }
        guard let load = Double(value.replacingOccurrences(of: ",", with: ".")), load.isFinite, load > 0 else { return nil }
        return load
    }

    var parsedReps: Int? {
        guard let count = Int(reps.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else { return nil }
        return count
    }

    var parsedRIR: Double? {
        guard let value = Double(rir.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              value.isFinite, (0...6).contains(value) else { return nil }
        return value
    }

    var canLog: Bool {
        parsedWeight != nil && parsedReps != nil && (rir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedRIR != nil)
    }

    /// RIR is optional, but the first Log tap on a set with no RIR typed asks for it instead of
    /// saving, so a tap that just missed the RIR box does not log the set and close the row
    /// (owner, 2026-11-04). A second tap saves without RIR. Pinned by SetEntryDraftTests.
    func shouldAskForRIR(alreadyAsked: Bool) -> Bool {
        canLog && !alreadyAsked && rir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Failed saves must leave the actual typed results available for retry.
    mutating func save(using persist: (Double, Int, Double?) -> Bool) -> Bool {
        guard canLog, let load = parsedWeight, let count = parsedReps,
              persist(load, count, parsedRIR) else { return false }
        self = SetEntryDraft()
        return true
    }
}

/// The rules for the two whole-session set sheets: the card's Edit sheet
/// (`AddExerciseWeightSheet`) and the history screen's Edit Log sheet
/// (`EditPerformanceLogSheet`). Both REWRITE a session's whole set list on save, so a row
/// they cannot read is not "skipped": it is deleted from the stored session.
///
/// That is how bodyweight sets were lost (bug audit 2026-11-17, F1). The inline logger stores
/// "BW" as 0 lb; both sheets filled such a set as "0", refused any load that was not above
/// zero, dropped the row, and wrote the remaining sets back over the session. A session
/// logged entirely at bodyweight could not be saved at all.
///
/// So, unlike `SetEntryDraft` (one set, typed fresh, with a Bodyweight button):
///  * "0" means bodyweight as well as "BW". These sheets use a number keypad, which cannot
///    type "BW", so 0 is the only way to enter bodyweight here.
///  * A row that cannot be read blocks the save and is named. It is never dropped.
///  * A completely empty row is ignored: nothing was entered, so nothing is lost.
///  * Blank or "0" reps on a row with a load save as 0 reps, which is what both sheets already
///    did and what such a set is stored as. The analysis ignores 0-rep sets.
///  * Stored loads and RIR are shown at full precision (`weightText`, `rirText`), so opening
///    a session and saving it without edits writes back the same weights, reps and RIR. The
///    sheets used one-decimal display text, which turned a 22.25 lb set into 22.2 on save.
///    (Each saved set still gets a new identifier; nothing stores those identifiers.)
/// Pinned by SetEntryDraftTests.
enum SessionSetSheetRules {
    struct Row: Equatable {
        var setNumber: Int
        var weightText: String
        var repsText: String
        var rirText: String
    }

    struct Outcome {
        /// Rows that will be stored, in the order given.
        var sets: [SetLogEntry]
        /// Set numbers of rows that hold something but cannot be read. Non-empty blocks save.
        var unreadableSetNumbers: [Int]

        var canSave: Bool { !sets.isEmpty && unreadableSetNumbers.isEmpty }
    }

    /// The text a stored load is shown as. Exactly 0 is bodyweight. The legacy "1 lb"
    /// stand-in stays "1": showing it as BW would rewrite that record to 0 on the next save,
    /// and those records are reinterpreted, never rewritten
    /// (`WorkoutProgressionEngine.bodyweightEquivalentThresholdLbs`).
    static func weightText(for weightLbs: Double) -> String {
        weightLbs == 0 ? "BW" : exactText(weightLbs)
    }

    /// A stored RIR at full precision.
    static func rirText(for rir: Double) -> String {
        exactText(rir)
    }

    /// "135" for a whole number, otherwise the shortest text that reads back as the same
    /// number ("22.25", not the one-decimal "22.2").
    private static func exactText(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    /// Bodyweight ("BW", any case, or 0) is 0. Anything else must be a finite load above 0.
    static func weight(from text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.caseInsensitiveCompare("BW") == .orderedSame { return 0 }
        guard let load = Double(value.replacingOccurrences(of: ",", with: ".")),
              load.isFinite, load >= 0 else { return nil }
        return load
    }

    /// Blank is 0 (see above); otherwise a whole number of at least 0.
    static func reps(from text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return 0 }
        guard let count = Int(value), count >= 0 else { return nil }
        return count
    }

    /// Blank is "no RIR". Otherwise 0 to 6, the same bounds as the inline logger.
    static func rir(from text: String) -> Double?? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return .some(nil) }
        guard let parsed = Double(value.replacingOccurrences(of: ",", with: ".")),
              parsed.isFinite, (0...6).contains(parsed) else { return nil }
        return .some(parsed)
    }

    static func evaluate(_ rows: [Row]) -> Outcome {
        var sets: [SetLogEntry] = []
        var unreadable: [Int] = []
        for row in rows {
            let blank = [row.weightText, row.repsText, row.rirText]
                .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if blank { continue }
            guard let weight = Self.weight(from: row.weightText),
                  let reps = Self.reps(from: row.repsText),
                  let rir = Self.rir(from: row.rirText) else {
                unreadable.append(row.setNumber)
                continue
            }
            sets.append(SetLogEntry(setNumber: row.setNumber, weightLbs: weight, repsCompleted: reps, rir: rir))
        }
        return Outcome(sets: sets, unreadableSetNumbers: unreadable)
    }

    /// One plain sentence naming the rows that block the save, or nil when none do.
    static func blockingMessage(for outcome: Outcome) -> String? {
        guard !outcome.unreadableSetNumbers.isEmpty else { return nil }
        let list = outcome.unreadableSetNumbers.map(String.init).joined(separator: ", ")
        let noun = outcome.unreadableSetNumbers.count == 1 ? "Set" : "Sets"
        return "\(noun) \(list): enter a weight (0 for bodyweight), whole-number reps, and RIR from 0 to 6, or clear the row."
    }
}
