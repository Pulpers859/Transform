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

    /// Failed saves must leave the actual typed results available for retry.
    mutating func save(using persist: (Double, Int, Double?) -> Bool) -> Bool {
        guard canLog, let load = parsedWeight, let count = parsedReps,
              persist(load, count, parsedRIR) else { return false }
        self = SetEntryDraft()
        return true
    }
}
