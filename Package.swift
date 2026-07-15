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
        .target(
            name: "TransformGeneratorCore",
            path: "Transform/Transform",
            sources: [
                // Service base + networking (ClaudeService's UIKit photo path is guarded
                // behind #if canImport(UIKit), so it compiles cleanly off-device).
                "ClaudeService.swift",
                "AnthropicClient.swift",
                "Config.swift",

                // Shared model layer.
                "Models.swift",
                "BodyAnalysisModels.swift",
                "WorkoutModels.swift",

                // Deterministic workout generator (the menu-locked planning core).
                "WorkoutGeneratorDebugModels.swift",
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
            dependencies: ["TransformGeneratorCore"],
            path: "Tests/TransformGeneratorCoreTests"
        )
    ]
)
