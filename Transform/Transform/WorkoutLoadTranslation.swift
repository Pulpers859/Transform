import Foundation

/// Carrying a known working load ACROSS a change of prescription.
///
/// The progression engine answers "same prescription — heavier, lighter, or hold?". It has no
/// answer at all when the prescription itself changes, and the generator is free to change it
/// every week. That gap produced the exact failure this type exists to prevent: a lifter who
/// maxed 2x10-14 at 35 lb was told to ADD load, in the same breath as being handed 3x15-20 —
/// a prescription needing roughly 30 lb. Nothing was wrong with either half on its own; nobody
/// owned the sentence in between.
///
/// The model is deliberately boring and standard:
///   * reps + reps-in-reserve = what the lifter could actually have done (capacity);
///   * Epley converts capacity to a common yardstick and back out at the new rep target;
///   * reps fall on later sets, so more sets means less load, independent of the rep change;
///   * round DOWN to a load the equipment can make.
///
/// Epley is used rather than Brzycki or a fixed-exponent power law because it is the only one
/// of the three that stays accurate where this lifter actually trains. Checked against the
/// standard %1RM reference table, RMS error: Epley 0.016, Brzycki 0.039, Lombardi 0.059 — and
/// at 20 reps Epley is near-exact (0.600 vs 0.600) while Brzycki reads 0.472 and would
/// prescribe a load roughly a fifth too light.
///
/// Foundation-only on purpose: this decides what the lifter is told to pick up, so it is in
/// the headless test target and its arithmetic is pinned by execution, not by inspection.
enum WorkoutLoadTranslation {

    /// Fraction of a one-rep max liftable for `maxReps` reps (Epley, inverted).
    ///
    /// The one-rep max here is a YARDSTICK for comparing rep ranges, not a claim about what the
    /// lifter could actually single. Nothing displays it.
    static func loadFraction(atMaxReps maxReps: Double) -> Double {
        guard maxReps > 0 else { return 1 }
        return 1.0 / (1.0 + maxReps / 30.0)
    }

    /// What the lifter proved they could do under the OLD prescription.
    struct Reference: Equatable {
        let loadLbs: Double
        let repsAchieved: Int
        /// Reps left in the tank: measured when logged, otherwise that session's target RIR.
        let reserveReps: Double
        /// True when `repsAchieved` equalled the top of the old range.
        ///
        /// Then the lifter stopped because the prescription said to, not because they ran out —
        /// so capacity is a LOWER BOUND, not a measurement (right-censored). Every estimate
        /// built on it therefore leans light, which is the safe direction, but callers that
        /// report confidence must not pretend the number is exact.
        let hitPrescribedCeiling: Bool

        var capacityReps: Double { Double(repsAchieved) + max(0, reserveReps) }
    }

    /// What the NEW prescription demands.
    struct Target: Equatable {
        let sets: Int
        /// The BOTTOM of the new range. Double progression enters a block at the floor and
        /// climbs to the ceiling; aiming at the ceiling would start the block already maxed.
        let repFloor: Int
        let targetRIR: Double
    }

    struct Outcome: Equatable {
        /// Rounded to a load the equipment can actually make. This is the number to show.
        let recommendedLoadLbs: Double
        let rawLoadLbs: Double
        /// Capacity the FIRST set needs so the LAST one still reaches the floor.
        let requiredFirstSetCapacity: Double
        let fatigueDecayPerSet: Double
        /// Recommended / reference. Below 1 means the new prescription needs less weight.
        let fractionOfReferenceLoad: Double
        let referenceWasCensored: Bool

        /// A swing this large is a red flag, not an instruction.
        ///
        /// It means either the prescription jumped further than one week should, or the history
        /// feeding it is wrong. Callers SURFACE this; they must not silently refuse to coach,
        /// and they must not quietly clamp the number into looking reasonable.
        var isImplausibleSwing: Bool {
            fractionOfReferenceLoad < 0.67 || fractionOfReferenceLoad > 1.5
        }
    }

    /// Coarse training zones, used only to judge how far a rep prescription MOVED.
    ///
    /// Deliberately blunt. The point is not to classify training styles, it is to answer one
    /// question — is this a normal week-to-week adjustment or a leap the load cannot follow in
    /// one step? Classified by the midpoint so 10-14 and 12-15 are neighbours rather than
    /// arbitrarily split by their endpoints.
    enum RepBand: Int, Comparable {
        case strength = 0   // 1-5
        case heavy          // 6-10
        case moderate       // 11-15
        case endurance      // 16+

        static func < (lhs: RepBand, rhs: RepBand) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func band(for range: RepRange) -> RepBand {
        let midpoint = (Double(range.low) + Double(range.high)) / 2
        switch midpoint {
        case ..<5.5:  return .strength
        case ..<10.5: return .heavy
        case ..<15.5: return .moderate
        default:      return .endurance
        }
    }

    /// How many bands a prescription moved. 0 means it stayed in the same zone.
    static func bandJump(from previous: RepRange, to next: RepRange) -> Int {
        abs(band(for: next).rawValue - band(for: previous).rawValue)
    }

    /// More than this in a single week is a leap, not an adjustment.
    static let maximumBandJumpPerWeek = 1

    /// Reps typically fall about a tenth per set at a fixed load. Population starting point,
    /// replaced by the lifter's own measured drop as soon as there is any.
    static let defaultFatigueDecayPerSet = 0.90
    static let minimumFatigueDecayPerSet = 0.80
    static let maximumFatigueDecayPerSet = 1.0

    static func translate(
        reference: Reference,
        target: Target,
        fatigueDecayPerSet: Double = defaultFatigueDecayPerSet,
        incrementLbs: Double
    ) -> Outcome? {
        guard reference.loadLbs > 0,
              reference.repsAchieved > 0,
              target.sets > 0,
              target.repFloor > 0,
              incrementLbs > 0
        else { return nil }

        let decay = min(max(fatigueDecayPerSet, minimumFatigueDecayPerSet), maximumFatigueDecayPerSet)
        let capacity = reference.capacityReps
        let yardstick = reference.loadLbs / loadFraction(atMaxReps: capacity)

        let finalSetCapacity = Double(target.repFloor) + max(0, target.targetRIR)
        let firstSetCapacity = finalSetCapacity / pow(decay, Double(target.sets - 1))

        let raw = yardstick * loadFraction(atMaxReps: firstSetCapacity)
        // DOWN, never nearest. Entering a block light costs one easy session; entering it heavy
        // costs weeks stuck under the rep floor, which is the failure this whole type exists to
        // avoid. The floor of one increment keeps a light isolation lift off zero.
        let rounded = max(incrementLbs, (raw / incrementLbs).rounded(.down) * incrementLbs)

        return Outcome(
            recommendedLoadLbs: rounded,
            rawLoadLbs: raw,
            requiredFirstSetCapacity: firstSetCapacity,
            fatigueDecayPerSet: decay,
            fractionOfReferenceLoad: rounded / reference.loadLbs,
            referenceWasCensored: reference.hitPrescribedCeiling
        )
    }

    /// The lifter's own per-set rep drop, measured from sessions where they actually did
    /// multiple working sets at one load.
    ///
    /// Shrunk toward the population value rather than trusted outright: one session with a
    /// bad last set is not a training characteristic. With no usable sessions this returns the
    /// population value unchanged, so the caller never has to special-case a new exercise.
    static func estimatedFatigueDecayPerSet(
        for canonicalExerciseKey: String,
        from snapshots: [WorkoutPerformanceLogSnapshot],
        lookback: Int = 6,
        priorWeight: Double = 2
    ) -> Double {
        let recent = snapshots
            .filter { $0.canonicalExerciseKey == canonicalExerciseKey }
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(max(1, lookback))

        var ratios: [Double] = []
        for snapshot in recent {
            let working = WorkingSetAnalysis.analyze(snapshot.setLogs).workingSets
                .sorted { $0.setNumber < $1.setNumber }
            guard working.count >= 2,
                  let first = working.first, let last = working.last,
                  first.reps > 0, last.reps > 0
            else { continue }
            // Per-set decay, not total: a 3-set session drops twice, a 2-set session once.
            ratios.append(pow(Double(last.reps) / Double(first.reps), 1.0 / Double(working.count - 1)))
        }

        guard !ratios.isEmpty else { return defaultFatigueDecayPerSet }
        // Median, not mean: one abandoned last set should not redefine how the lifter fatigues.
        let sorted = ratios.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2

        let n = Double(ratios.count)
        let blended = (median * n + defaultFatigueDecayPerSet * priorWeight) / (n + priorWeight)
        return min(max(blended, minimumFatigueDecayPerSet), maximumFatigueDecayPerSet)
    }
}
