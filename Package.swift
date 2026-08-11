// swift-tools-version: 5.9
import PackageDescription

// Headless test harness for Transform's deterministic workout-generation core.
//
// WHY THIS EXISTS
// ---------------
// The iOS app is validated by building in Xcode and running on a physical iPhone.
// That leaves the generator's pure planning logic (menu-lock -> weekly set allocation
// -> validation -> procedural fallback) with NO automated regression coverage, so every
// change ships "correct-by-inspection". This package compiles ONLY the network-free,
// UI-free generator core + its model dependencies so it can be exercised with plain
// `swift test` on any macOS machine or a GitHub `macos` runner — no simulator, no device.
//
// It does NOT copy source. The library target compiles the real app files in place, so
// the tests always run against the shipping code. The Xcode app target is untouched.
//
// FIRST-RUN NOTE (source closure)
// -------------------------------
// The `sources` list below is the deterministic-generator dependency closure determined
// by inspection. Swift's transitive type resolution can only be finalized by a compiler.
// If `swift build` reports "cannot find type X in scope", add the file that defines X to
// the `sources` list (all such files live under Transform/Transform and are Foundation /
// SwiftData / SwiftUI only — no UIKit). See docs/generator-test-harness.md.
let package = Package(
    name: "TransformGeneratorHarness",
    platforms: [
        // SwiftData / @Model model types require macOS 14+.
        .macOS(.v14)
    ],
    targets: [
        // The target is named "Transform" to match the iOS app's module name, so that
        // module-qualified references in the sources (e.g. `Transform.formatWeight`)
        // resolve within this module.
        .target(
            name: "Transform",
            path: "Transform/Transform",
            sources: [
                // Service base + networking (ClaudeService's UIKit photo path is guarded
                // behind #if canImport(UIKit), so it compiles cleanly off-device).
                "ClaudeService.swift",
                "AnthropicClient.swift",
                "AnthropicAPIKeyStore.swift",
                "Config.swift",
                // Harness-only shims for free functions that live in UIKit/SwiftUI files
                // (e.g. formatWeight in DesignSystem.swift) which are excluded here.
                // Guarded so it is empty in the iOS app build.
                "HarnessShims.swift",
                // Peripheral types referenced by the files above: AppLifecycleSnapshot
                // (AnthropicClient error diagnostics; UIKit already guarded in-file) and
                // AdaptiveMacroOverride (Config macro-target calc). Both Foundation-safe.
                "AppLifecycleMonitor.swift",
                "AdaptiveInsights.swift",
                "NutritionGeneratorService.swift",
                // Structured sleep-recovery state + tier policy (Foundation-only) consumed
                // by the calibration pass; written on-device by SleepTracking.swift.
                "RecoveryState.swift",
                // Day-anchored sleep aggregation math + quick-log wake-date crediting
                // (Foundation-only core behind SleepTrendBuilder).
                "SleepAggregationCore.swift",
                // Foundation-only reconciliation core for importing sleep from an
                // external timing source (HealthKit): coalescing + plausibility +
                // never-overwrite-manual reconcile. The HKHealthStore I/O that feeds
                // it lives in SleepHealthKitService.swift and is NOT in this closure.
                "SleepHealthImportCore.swift",

                // Shared model layer. (Models.swift — the sleep/nutrition/weight
                // persistence models — is intentionally NOT here: nothing in the
                // generator closure references it, and it drags in unrelated types.)
                "BodyAnalysisModels.swift",
                "WorkoutModels.swift",
                // Execution-cue authoring: movement-pattern/equipment keying plus the
                // day-scoped uniqueness pass. Foundation-only, and the content it emits must
                // survive the validator's execution-only rules — a banned fragment here is a
                // HARD generation failure that discards a paid AI week, so it gets real
                // regression coverage rather than shipping correct-by-inspection.
                "CoachingVoice.swift",
                // One resolved answer to "what happened on this exercise?". Replaces four
                // independently-read data sources on different time windows, which is how the
                // card came to contradict itself on screen (a Best set TODAY presented beside
                // a Last that excludes today, a zero-set Modified lift wearing the same green
                // check as one actually performed). Foundation-only.
                "ExerciseSessionSummary.swift",
                // Session completion / clock state machine. Foundation + SwiftData only
                // (all its UI callers stay out of this closure), so the rules that decide
                // when a day is finished and when the clock closes get real regression
                // coverage instead of shipping correct-by-inspection.
                "SessionLifecycle.swift",
                "WorkoutProgressionEngine.swift",
                "WorkoutEffortGovernance.swift",

                // Deterministic workout generator (the menu-locked planning core).
                "WorkoutGeneratorDebugModels.swift",
                "WorkoutGenerationDiagnostics.swift",
                "WorkoutGeneratorService.swift",
                "WorkoutGeneratorService+PlanningTypes.swift",
                "WorkoutGeneratorService+MetadataProfiles.swift",
                "WorkoutGeneratorService+PriorityIntent.swift",
                "WorkoutGeneratorService+TrainingIntentBlueprint.swift",
                "WorkoutGeneratorService+ExerciseSelection.swift",
                "WorkoutGeneratorService+FocusCoachingContext.swift",
                "WorkoutGeneratorService+ParsingValidation.swift",
                "WorkoutGeneratorService+FallbackCore.swift",
                "WorkoutGeneratorService+Requests.swift"
            ]
        ),
        .testTarget(
            name: "TransformGeneratorCoreTests",
            dependencies: ["Transform"],
            path: "Tests/TransformGeneratorCoreTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
