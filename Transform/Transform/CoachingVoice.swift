import Foundation

/// Execution-cue authoring for procedurally built exercises.
///
/// WHY THIS EXISTS
/// ---------------
/// The cue pool it replaces (`techniqueCue` in +FocusCoachingContext) held exactly TWO
/// sentences per muscle family and rotated them with `(index + name.count) % 2`. On a push
/// day with four chest movements that is not a risk of repetition — it is a guarantee of it.
/// A live Day 11 showed Incline Dumbbell Press and Machine Incline Press carrying the same
/// sentence word for word, and Machine Chest Press and Dumbbell Bench Press carrying the
/// other one. The Cue box is the tallest recurring element on a card, so roughly two fifths
/// of the day's scroll was text the lifter had already read. Nothing erodes trust in a
/// coaching app faster than catching it repeat itself.
///
/// Two changes fix that at the root:
///
/// 1. Cues are keyed by MOVEMENT PATTERN + EQUIPMENT, not by muscle family. An incline
///    dumbbell press and a machine incline press are different jobs for the lifter's hands
///    even though both are "chest", and they now read differently because they ARE indexed
///    differently.
/// 2. Assignment is DAY-SCOPED (`assignCues`). The day is resolved as a unit and a cue
///    already spoken on that day is never spoken again, falling down a candidate ladder
///    instead. Duplication on one screen stops being unlikely and becomes unrepresentable.
///
/// HARD CONSTRAINTS (do not relax without reading the incident history)
/// -------------------------------------------------------------------
/// * Cues are EXECUTION-ONLY. The deterministic progression banner owns every statement
///   about load and reps. A previous design appended progression prose to notes and created
///   the two-voices contradiction the display filter then had to strip sentence by sentence
///   (`coachingSentences` in WorkoutDayDetailView). Every string here must survive that
///   filter untouched — see `CoachingVoiceAudit.forbiddenFragments`, which mirrors it.
/// * No string interpolates the exercise name. The retired template produced
///   "...across all sets of Dip (Assisted or Weighted)." — a database row read aloud.
/// * Cues never mention RIR, rep counts, percentages, or "reserve": the deload filter strips
///   those, and the structured `targetRIR` field already carries effort.
/// * Selection is DETERMINISTIC and stable for a given day. Notes are persisted at generation
///   time; a randomised or clock-dependent pick would churn stored text on every regen.
enum CoachingVoice {

    // MARK: - Movement taxonomy

    /// What the lifter's body is actually doing. Deliberately coarser than an exercise name
    /// and finer than a muscle group — that middle altitude is where technique advice is
    /// both true and specific.
    enum Pattern: String, CaseIterable, Sendable {
        case inclinePress
        case horizontalPress
        case chestFly
        case dip
        case overheadPress
        case lateralRaise
        case rearDelt
        case verticalPull
        case horizontalPull
        case pullover
        case shrug
        case bicepCurl
        case tricepExtension
        case squat
        case hinge
        /// A bridge, not a hinge. Kept separate because hinge cues ("push the hips back",
        /// "keep the bar close to the legs") describe the wrong axis for a thrust.
        case hipThrust
        case lunge
        case legPress
        case legCurl
        /// Ankle-anchored bodyweight knee flexion (the Nordic). Split off `.legCurl` because
        /// every machine-curl cue starts from hardware the lifter does not have here: there is
        /// no pad under the hips to pin and no stack to stop short of. A lifter told to "keep
        /// the hips pinned to the pad" on a Nordic is being coached on a different exercise.
        case nordicCurl
        case legExtension
        case calfRaise
        case core
        case general
    }

    /// How the load is held. Changes the cue meaningfully: a machine sets the path for you,
    /// a dumbbell makes you own it.
    enum Equipment: String, CaseIterable, Sendable {
        case machine
        case cable
        case dumbbell
        case barbell
        case bodyweight
        case unspecified
    }

    // MARK: - Public entry point

    /// Resolves one execution cue per exercise, guaranteeing no two exercises in the same
    /// list receive the same sentence.
    ///
    /// Order matters and is preserved: callers pass exercises in their on-screen order, so
    /// the most specific cue lands on the first (usually the anchor) movement and later
    /// duplicates of a pattern take progressively more general phrasing.
    ///
    /// - Parameter exercises: `(name, muscleTarget)` pairs in day order.
    /// - Returns: cues parallel to `exercises`.
    /// - Parameter avoidEndRangeShoulder: set when the analysis flagged the shoulder. Cue text
    ///   was previously a pure function of pattern and equipment, so a lifter with a flagged
    ///   shoulder could be told to "descend until the upper arms break parallel" on a dip while
    ///   the exercise-selection layer was busy penalising that exact joint position.
    static func assignCues(
        for exercises: [(name: String, muscleTarget: String)],
        avoidEndRangeShoulder: Bool = false
    ) -> [String] {
        var spoken = Set<String>()
        var assigned: [String] = []
        assigned.reserveCapacity(exercises.count)

        for exercise in exercises {
            let pattern = pattern(forName: exercise.name, muscleTarget: exercise.muscleTarget)
            let equipment = equipment(forName: exercise.name)
            let cue = firstUnspoken(
                from: candidates(
                    pattern: pattern,
                    equipment: equipment,
                    avoidEndRangeShoulder: avoidEndRangeShoulder
                ),
                spoken: spoken
            )
            spoken.insert(cue)
            assigned.append(cue)
        }

        return assigned
    }

    /// Single-exercise convenience for callers that repair one note in isolation (an AI note
    /// that came back empty). Without day context it cannot guarantee day-wide uniqueness,
    /// so it takes the cues already present on the day and avoids them.
    static func cue(
        forName name: String,
        muscleTarget: String,
        avoiding spoken: Set<String> = [],
        avoidEndRangeShoulder: Bool = false
    ) -> String {
        firstUnspoken(
            from: candidates(
                pattern: pattern(forName: name, muscleTarget: muscleTarget),
                equipment: equipment(forName: name),
                avoidEndRangeShoulder: avoidEndRangeShoulder
            ),
            spoken: spoken
        )
    }

    /// Walks the candidate ladder and takes the first sentence this day has not used. If the
    /// ladder is somehow exhausted (a day with more exercises of one pattern than the pool
    /// has phrasings) it returns the last candidate rather than an empty string — a repeated
    /// true cue beats a blank box.
    ///
    /// `universalCues` is never empty, so `candidates` is never empty and `.last` always
    /// yields. A third fallback used to sit here holding a byte-identical copy of
    /// `universalCues[0]`: unreachable, and a second place for the same sentence to be edited
    /// out of step with the first.
    private static func firstUnspoken(from candidates: [String], spoken: Set<String>) -> String {
        candidates.first { !spoken.contains($0) } ?? candidates.last ?? universalCues[0]
    }

    // MARK: - Candidate ladder

    /// Most specific first: equipment-qualified cues for this pattern, then the pattern's
    /// general cues, then the universal pool. `assignCues` walks this until it finds
    /// something unspoken, so a second incline press on the same day naturally slides to a
    /// different rung rather than repeating the first.
    private static func candidates(
        pattern: Pattern,
        equipment: Equipment,
        avoidEndRangeShoulder: Bool = false
    ) -> [String] {
        var ladder: [String] = []
        ladder.append(contentsOf: equipmentCues[Key(pattern: pattern, equipment: equipment)] ?? [])
        ladder.append(contentsOf: patternCues[pattern] ?? [])

        // Removing, not replacing. The protective phrasing a flagged shoulder needs is ALREADY
        // written one rung down — "keep the shoulders pulled away from your ears" on a dip,
        // "raise through the scapular plane" on a lateral raise, "stop the negative when your
        // hands reach chest depth" on a machine press. Dropping the end-range cue promotes the
        // cue that was going to be second choice anyway, so this adds no new sentences to
        // maintain and every remaining candidate is already audited content.
        if avoidEndRangeShoulder {
            ladder.removeAll { endRangeShoulderCues.contains($0) }
        }

        // Appended after the filter: the universal pool carries no joint-specific range
        // instruction, so it is always safe and always keeps the ladder non-empty.
        ladder.append(contentsOf: universalCues)
        return ladder
    }

    /// Cues that deliberately drive the shoulder toward end range — deep humeral extension under
    /// load, a loaded stretch at the bottom of a press, or abduction past shoulder height. Sound
    /// coaching for an uninjured lifter, and the classic aggravators for an impinged one.
    ///
    /// Every entry must appear VERBATIM in `equipmentCues` or `patternCues`;
    /// `CoachingVoiceAudit.orphanedEndRangeShoulderCues()` fails the tests if one drifts, so this
    /// cannot rot into a list of strings that no longer match anything.
    static let endRangeShoulderCues: Set<String> = [
        "Lower until your upper arms sit just below the torso line, then press without letting the dumbbells drift back over your face.",
        "Let the carriage come back far enough to feel a stretch across the top of the chest before reversing it.",
        "Descend until the upper arms break parallel, then drive up without letting the shoulders roll forward.",
        "Stop just past shoulder height and lower slowly — the pad makes it easy to fall out of tension at the bottom.",
        "Take three seconds to lower and stay in contact with the stretch before you reverse.",
        "Control the lowering phase and let the chest stretch before reversing the rep.",
        "Control the descent rather than dropping into the stretch."
    ]

    /// `Sendable` explicitly: the cue tables are `static let` dictionaries keyed by this type,
    /// and under Swift 6 strict concurrency a static stored property must be of a Sendable
    /// type. Inference would almost certainly get there on its own; stating it means a future
    /// stored property on this key cannot silently break the build.
    private struct Key: Hashable, Sendable {
        let pattern: Pattern
        let equipment: Equipment
    }

    // MARK: - Classification

    /// Order is significant: the first match wins, so narrower phrases are tested before the
    /// broad ones they contain ("incline press" before "press", "leg curl" before "curl").
    ///
    /// Two hazards this ordering has already been bitten by, both verified against the shipped
    /// exercise catalog (see `CoachingVoiceCatalogTests`):
    ///
    /// * SUBSTRINGS THAT SPAN WORDS. `"t bar"` was a needle for rows and matched inside
    ///   "fla{t bar}bell", so Flat Barbell Bench Press — the anchor of the Push catalog — was
    ///   classified as a horizontal PULL and coached "set the scapula, then pull with the
    ///   elbows". Needles must be anchored or unambiguous; "row" already covers every T-bar
    ///   row without the hazard.
    /// * A MOVEMENT WORD SHADOWING THE ONE THAT MATTERS. "incline dumbbell" caught Incline
    ///   Dumbbell *Curl* and Low-Incline Dumbbell *Fly*; "fly"/"pec deck" caught Reverse Pec
    ///   Deck and every rear-delt fly. The isolation word is the meaningful one, so the
    ///   isolation patterns are now tested BEFORE the press/fly families they sit inside.
    static func pattern(forName name: String, muscleTarget: String) -> Pattern {
        let text = normalize("\(name) \(muscleTarget)")

        // Legs first — "leg press" and "leg curl" contain "press" and "curl".
        // "seated curl" / "lying curl" are deliberately NOT here: a seated dumbbell curl is a
        // biceps movement, and matching them would classify it as a hamstring curl and coach
        // the lifter to pin their hips to a pad.
        // Nordic before the leg-curl family it sits inside: "Nordic Hamstring Curl" also
        // contains "hamstring curl", and the machine cues are wrong for it. The Glute-Ham
        // Raise deliberately stays with `.legCurl` — a GHD really does put the hips on a pad,
        // so that cue is literally true there.
        if matches(text, ["nordic"]) { return .nordicCurl }
        if matches(text, ["leg curl", "hamstring curl", "glute ham", "glute-ham"]) { return .legCurl }
        if matches(text, ["leg extension", "quad extension"]) { return .legExtension }
        // Calf before leg press: "Leg Press Calf Raise" is a calf raise performed on a sled.
        if matches(text, ["calf", "calves"]) { return .calfRaise }
        if matches(text, ["leg press", "hack squat"]) { return .legPress }
        if matches(text, ["lunge", "split squat", "step up", "step-up"]) { return .lunge }
        if matches(text, ["squat", "goblet"]) { return .squat }
        // Hip thrust is a bridge, not a hinge: "push the hips back" and "keep the bar close to
        // the legs" describe the wrong axis entirely.
        if matches(text, ["hip thrust", "glute bridge"]) { return .hipThrust }
        if matches(text, ["deadlift", "romanian", "rdl", "good morning", "hip hinge", "back extension"]) { return .hinge }

        // Isolation words before the compound families that contain them.
        if matches(text, ["rear delt", "rear deltoid", "reverse fly", "reverse pec", "face pull", "reverse cable crossover"]) { return .rearDelt }
        if matches(text, ["lateral raise", "side raise", "lateral machine", "side lateral"]) { return .lateralRaise }
        if matches(text, ["shrug", "trap raise"]) { return .shrug }
        if matches(text, ["curl", "bicep", "brachialis", "preacher", "hammer"]) { return .bicepCurl }
        // Straight-arm pulldown is a lat isolation over a fixed elbow, not a vertical pull —
        // the bar travels to the thighs, so "stop at your collarbone" is backwards.
        if matches(text, ["pullover", "pull-over", "straight arm pull", "straight-arm pull"]) { return .pullover }
        if matches(text, ["fly", "flye", "flies", "pec deck", "peck deck", "crossover", "cross-over"]) { return .chestFly }

        if matches(text, ["dip"]) { return .dip }
        // Requires BOTH tokens so "Incline Dumbbell Curl" cannot be read as a press.
        if text.contains("incline") && text.contains("press") { return .inclinePress }
        // "landmine press" is an angled press, closer to an incline than an overhead.
        if matches(text, ["landmine press"]) { return .inclinePress }
        if matches(text, ["overhead press", "shoulder press", "military press", "arnold press"]) { return .overheadPress }

        if matches(text, ["pulldown", "pull-down", "pull up", "pull-up", "pullup", "chin up", "chin-up", "chinup", "lat pull"]) { return .verticalPull }
        // NOT "t bar" — it matches inside "flat barbell". "row" covers T-bar rows already.
        if matches(text, ["row"]) { return .horizontalPull }

        // Close-grip bench is a triceps-biased PRESS; cueing "let only the forearms travel"
        // on a compound barbell press is wrong and unsafe.
        // Matched on the two tokens rather than the phrase: the catalog name is "Close-Grip
        // BARBELL Bench Press", so a contiguous "close-grip bench" needle misses it and the
        // movement falls through to the triceps branch on the bare word "close-grip".
        if text.contains("close") && text.contains("bench") { return .horizontalPress }
        // "kickback" qualified: a glute kickback is not a triceps movement.
        if matches(text, ["pushdown", "push-down", "pressdown", "press-down", "skull", "overhead extension", "tricep extension", "triceps extension", "triceps kickback", "tricep kickback", "close grip", "close-grip", "jm press"]) { return .tricepExtension }

        if matches(text, ["crunch", "plank", "ab wheel", "leg raise", "knee raise", "pallof", "oblique", "dead bug", "hollow", "rollout"]) { return .core }

        // Broad press last: anything still unmatched that presses is a horizontal press.
        if matches(text, ["bench press", "chest press", "press"]) { return .horizontalPress }

        return .general
    }

    static func equipment(forName name: String) -> Equipment {
        let text = normalize(name)
        // Cable before machine: a "cable machine" movement is coached like a cable.
        if matches(text, ["cable", "crossover", "cross-over", "pulldown", "pull-down", "pushdown", "push-down", "pressdown", "rope"]) { return .cable }
        // Smith before machine, and classified as a BARBELL: it is a bar on a fixed path, so
        // machine cues about seat height, handles and a carriage describe equipment that is
        // not there.
        if matches(text, ["smith"]) { return .barbell }
        if matches(text, ["machine", "hammer strength", "pec deck", "peck deck", "sled", "lever"]) { return .machine }
        if matches(text, ["dumbbell", "db ", " db", "goblet", "arnold"]) { return .dumbbell }
        if matches(text, ["barbell", "bb ", "ez bar", "ez-bar", "landmine", "t-bar", "trap bar"]) { return .barbell }
        if matches(text, ["bodyweight", "body weight", "assisted", "weighted", "pull up", "pull-up", "pullup", "chin up", "chin-up", "chinup", "dip", "push up", "push-up", "pushup", "plank", "nordic"]) { return .bodyweight }
        return .unspecified
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    private static func matches(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    // MARK: - Cue content
    //
    // Every sentence below is execution technique and nothing else. Before adding one, run
    // `CoachingVoiceAudit.violations(in:)` — it enforces the display filter's fragment list
    // so a new cue cannot silently be stripped to nothing on screen.

    /// Equipment-qualified phrasings. These are the top rung of the ladder, so they are what
    /// a lifter reads on the first movement of a pattern.
    private static let equipmentCues: [Key: [String]] = [
        Key(pattern: .inclinePress, equipment: .dumbbell): [
            "Set the bench near thirty degrees and let the dumbbells travel slightly wider than a flat press so the clavicular fibres take the work.",
            "Lower until your upper arms sit just below the torso line, then press without letting the dumbbells drift back over your face."
        ],
        Key(pattern: .inclinePress, equipment: .machine): [
            "Set the seat so the handles line up with your upper chest, not your collarbone, and drive straight out along that line.",
            "Let the carriage come back far enough to feel a stretch across the top of the chest before reversing it."
        ],
        Key(pattern: .inclinePress, equipment: .barbell): [
            "Keep your shoulder blades pinned to the bench and touch the bar high on the chest, just under the collarbone.",
            "Drive your feet into the floor and press slightly back toward your eyes rather than straight up off the chest."
        ],
        Key(pattern: .horizontalPress, equipment: .dumbbell): [
            "Keep your wrists stacked over your elbows and lower until the dumbbells sit level with your chest, not below it.",
            "Press the dumbbells together lightly as you drive up so the pecs stay switched on at the top."
        ],
        Key(pattern: .horizontalPress, equipment: .machine): [
            "Set the seat height so the handles sit at mid-chest and your elbows track just under shoulder height.",
            "Stop the negative when your hands reach chest depth — going past the machine's path loads the shoulder, not the chest."
        ],
        Key(pattern: .horizontalPress, equipment: .barbell): [
            "Pull the bar apart as you unrack it and keep that tension so the shoulder blades stay set on the bench.",
            "Touch the same point on your chest every rep and keep your forearms vertical at the bottom."
        ],
        Key(pattern: .verticalPull, equipment: .bodyweight): [
            "Start from a full hang with the shoulders pulled down, then lead with the elbows rather than the chin.",
            "Control the descent all the way to straight arms instead of dropping into the next rep."
        ],
        Key(pattern: .verticalPull, equipment: .cable): [
            "Let the shoulders rise slightly at the top of each rep, then pull them down first and follow with the elbows.",
            "Keep the torso close to upright and stop the bar at your collarbone — dragging it lower turns it into a row."
        ],
        Key(pattern: .horizontalPull, equipment: .cable): [
            "Set the shoulder blade before the elbow moves, and let the handle come to your waist rather than your ribs.",
            "Keep the torso still and let the arms do the travelling so the back keeps the tension."
        ],
        Key(pattern: .horizontalPull, equipment: .dumbbell): [
            "Support the torso so it cannot rock, and pull the dumbbell toward your hip with the elbow close to your side.",
            "Pause briefly with the shoulder blade fully retracted before lowering under control."
        ],
        Key(pattern: .lateralRaise, equipment: .machine): [
            "Set the pads against your outer forearms and lead with the elbows so the pads travel, not your hands.",
            "Stop just past shoulder height and lower slowly — the pad makes it easy to fall out of tension at the bottom."
        ],
        Key(pattern: .lateralRaise, equipment: .dumbbell): [
            "Keep a soft elbow and raise slightly in front of your body rather than straight out to the side.",
            "Let the little finger lead marginally higher than the thumb and stop level with the shoulder."
        ],
        Key(pattern: .lateralRaise, equipment: .cable): [
            "Stand tall with the cable behind your back so tension holds through the bottom of every rep.",
            "Keep the working shoulder pressed down and let the arm sweep through a clean arc without a shrug."
        ],
        Key(pattern: .dip, equipment: .bodyweight): [
            "Lean the torso forward and keep it there through the whole set so the chest keeps the work.",
            "Descend until the upper arms break parallel, then drive up without letting the shoulders roll forward."
        ],
        Key(pattern: .tricepExtension, equipment: .cable): [
            "Fix the elbows against your sides and let only the forearms move through the rep.",
            "Keep a slight forward lean and finish each rep with the elbows fully straight before releasing."
        ],
        Key(pattern: .bicepCurl, equipment: .dumbbell): [
            "Keep the elbows just in front of your ribs and stop the upswing before the forearms reach vertical.",
            "Lower under control all the way to straight arms so the bottom of the range still counts."
        ],
        Key(pattern: .squat, equipment: .barbell): [
            "Brace against your belt line before you unrack and hold that brace until the rep is finished.",
            "Push the floor apart with your feet and keep the bar tracking over mid-foot the whole way down."
        ],
        Key(pattern: .overheadPress, equipment: .machine): [
            "Set the seat so the handles start level with your ears and press straight up from there.",
            "Keep your back against the pad and stop just short of locking the elbows."
        ],
        Key(pattern: .legPress, equipment: .machine): [
            "Keep the lower back flat against the pad and stop the descent the moment the pelvis starts to tuck.",
            "Drive through the whole foot and stop just short of locking the knees at the top."
        ]
    ]

    /// Pattern-level phrasings — the second rung. A day's third movement of one pattern lands
    /// here, which is why each pool carries several genuinely different ideas rather than
    /// restatements of one.
    private static let patternCues: [Pattern: [String]] = [
        .inclinePress: [
            "Keep the ribs down so the bench angle does the work instead of your lower back arching to meet it.",
            "Take three seconds to lower and stay in contact with the stretch before you reverse.",
            "Keep the elbows tucked to roughly forty-five degrees from the torso rather than flared straight out."
        ],
        .horizontalPress: [
            "Keep the shoulder blades retracted and driven into the bench for the whole set.",
            "Control the lowering phase and let the chest stretch before reversing the rep.",
            "Keep your forearms vertical through the press so the load stays over the working joint.",
            "Finish each rep short of a hard lockout so tension stays on the chest."
        ],
        .chestFly: [
            "Keep a fixed soft bend in the elbow and open only at the shoulder.",
            "Stop the stretch where you feel the chest rather than the front of the shoulder.",
            "Squeeze for a beat at the top before letting the arms travel back out."
        ],
        .dip: [
            "Keep the shoulders pulled away from your ears at the bottom of every rep.",
            "Control the descent rather than dropping into the stretch."
        ],
        .overheadPress: [
            "Squeeze the glutes and keep the ribs down so the press does not turn into a lean-back.",
            "Keep the bar path close to the face and finish with the arms stacked over the shoulders.",
            "Lower to the point where the upper arms reach shoulder height before pressing again."
        ],
        .lateralRaise: [
            "Keep the ribs down and raise through the scapular plane so the delts stay loaded without shrugging.",
            "Pause briefly at the top to remove momentum from each repetition.",
            "Keep the neck long and the traps quiet — the shoulder should be doing all of the lifting."
        ],
        .rearDelt: [
            "Keep the chest supported and lead with the elbows so the rear delts carry the movement.",
            "Stop when the arms reach the torso line rather than driving them behind it.",
            "Keep the movement slow enough that no swing contributes to the rep."
        ],
        .verticalPull: [
            "Set the shoulder blade down first, then pull with the elbows to keep the lats doing the work.",
            "Avoid leaning back through the rep so tension stays in the back rather than momentum.",
            "Control the lengthening phase and let the shoulders travel up at the top before the next rep."
        ],
        .horizontalPull: [
            "Initiate each rep by setting the scapula, then pull with the elbows.",
            "Keep the torso braced and still so the back works instead of the hips.",
            "Hold the contracted position for a beat before letting the weight travel back out."
        ],
        .pullover: [
            "Keep the elbows fixed and move only at the shoulder so the lats own the range.",
            "Stop the reach where the ribs want to flare rather than pushing past it."
        ],
        .shrug: [
            "Move straight up and down without rolling the shoulders.",
            "Hold the top position briefly and lower under control to a full stretch."
        ],
        .bicepCurl: [
            "Keep the elbows fixed and the torso still so nothing swings into the rep.",
            "Control the lowering phase and reach full extension before curling again.",
            "Keep the wrists neutral so the forearms do not take over the movement."
        ],
        .tricepExtension: [
            "Keep the elbows fixed and let only the forearms travel.",
            "Reach a full stretch at the top of the range before extending.",
            "Keep the shoulders still so the movement stays isolated to the elbow."
        ],
        .squat: [
            "Brace before every rep and keep a controlled descent to hold joint position under load.",
            "Keep the knees tracking over the toes and the torso angle constant.",
            "Descend to the depth you can hold position at, and own that depth every rep."
        ],
        .hipThrust: [
            "Drive through the heels and finish with the hips level, ribs down rather than arched.",
            "Pause at the top with the glutes hard before letting the hips travel back down.",
            "Keep the chin tucked and the shins vertical so the hips do the work."
        ],
        .hinge: [
            "Keep the spine neutral and push the hips back rather than bending at the waist.",
            "Keep the bar or dumbbells close to the legs through the whole range.",
            "Feel the hamstrings lengthen and stop the descent before the back rounds."
        ],
        .lunge: [
            "Keep the front shin roughly vertical and the torso tall.",
            "Control the descent and keep the hips square through the rep."
        ],
        .legPress: [
            "Keep the lower back flat against the pad through the whole range.",
            "Drive through the whole foot rather than the toes."
        ],
        .legCurl: [
            "Keep the hips pinned to the pad so the movement stays at the knee.",
            "Control the return and stop just short of the weight resting between reps."
        ],
        .nordicCurl: [
            "Hold a straight line from knees to shoulders so the knee is the only joint that bends.",
            "Lower yourself as slowly as you can hold, then push off the floor with your hands to return."
        ],
        .legExtension: [
            "Keep the back against the pad and extend without kicking the weight up.",
            "Pause briefly at full extension before lowering under control."
        ],
        .calfRaise: [
            "Take a full stretch at the bottom and a hard pause at the top of every rep.",
            "Keep the knee angle constant so the calf works through the whole range."
        ],
        .core: [
            "Move slowly and keep the ribs pulled toward the hips throughout.",
            "Breathe out through the hardest part of the rep and keep the brace on."
        ],
        .general: [
            "Use a controlled lowering phase and a stable setup to keep tension on the target muscle.",
            "Prioritise a full range and repeatable mechanics over anything else in the set."
        ]
    ]

    /// Bottom rung. Broad but still true — these only appear when a day stacks more movements
    /// of one pattern than the pattern pool covers.
    private static let universalCues: [String] = [
        "Set your position before the first rep and keep that position identical on every rep after it.",
        "Own the lowering phase; that is where most of the stimulus is bought.",
        "Keep the working joint under tension from the first rep to the last.",
        "Move only the joints the exercise asks for and keep everything else quiet.",
        "Match your breathing to the rep so the brace never drops mid-set."
    ]
}

/// Self-check for cue content. The display layer strips sentences containing progression or
/// recap language, so a cue that trips it renders as an empty box on the card — a silent,
/// invisible failure. This mirrors the filter's fragment list so the same mistake is caught
/// by a test instead of by the lifter.
enum CoachingVoiceAudit {

    /// Mirrors the strip lists in `WorkoutDayDetailView.coachingSentences`. Kept as a literal
    /// copy on purpose: the display filter is UI-layer and this type stays Foundation-only so
    /// it can be exercised headlessly. If the filter gains a fragment, add it here too.
    /// Composed from `ProgressionProseFragments`, never retyped.
    ///
    /// This constant used to be a hand-copy of the display filter's strip lists. Copies drift:
    /// it was missing six validator fragments, so a cue could pass this audit and still hard-
    /// fail generation. Composition makes that failure mode structurally impossible — a
    /// fragment added to the rule is added here by construction.
    static let forbiddenFragments: [String] = ProgressionProseFragments.all

    /// Fragments found in `cue`, lowercased. Empty means the cue survives the display filter.
    static func violations(in cue: String) -> [String] {
        let normalized = cue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return forbiddenFragments.filter { normalized.contains($0) }
    }

    /// Entries of `endRangeShoulderCues` that no longer match any cue the voice can emit.
    ///
    /// A filter keyed on exact strings is only as good as its strings. If a cue is reworded and
    /// this set is not, the filter silently stops protecting a flagged shoulder — a safety rule
    /// that fails open and looks fine. Non-empty here means exactly that has happened.
    static func orphanedEndRangeShoulderCues() -> [String] {
        let emittable = Set(allCues())
        return CoachingVoice.endRangeShoulderCues.subtracting(emittable).sorted()
    }

    /// Every cue string the voice can emit, for exhaustive testing.
    static func allCues() -> [String] {
        var cues: [String] = []
        // Drive it through the public surface so the audit can never drift from what ships:
        // any pattern/equipment pair the classifier can produce is reachable here.
        for pattern in CoachingVoice.Pattern.allCases {
            for equipment in CoachingVoice.Equipment.allCases {
                cues.append(contentsOf: CoachingVoice.cueLadderForAudit(pattern: pattern, equipment: equipment))
            }
        }
        return Array(Set(cues)).sorted()
    }
}

extension CoachingVoice {
    /// Test-only reach-through to the candidate ladder. `CoachingVoiceAudit` needs to see
    /// every emittable string, and routing it through the real ladder means the audit cannot
    /// drift from production content.
    static func cueLadderForAudit(
        pattern: Pattern,
        equipment: Equipment,
        avoidEndRangeShoulder: Bool = false
    ) -> [String] {
        candidates(pattern: pattern, equipment: equipment, avoidEndRangeShoulder: avoidEndRangeShoulder)
    }
}
