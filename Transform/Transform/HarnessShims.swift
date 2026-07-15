// Harness-only shims for the headless macOS generator test target.
//
// Some free functions the generator core references live in UIKit/SwiftUI files
// (e.g. `formatWeight` in DesignSystem.swift) that are intentionally excluded from
// the test package. This file supplies those symbols — but ONLY when UIKit is
// unavailable (i.e. the macOS test build). In the iOS app build,
// `canImport(UIKit)` is true, so this whole file compiles to nothing and never
// conflicts with the real definitions.
#if !canImport(UIKit)
import Foundation

/// Mirror of `formatWeight(_:)` in DesignSystem.swift (a SwiftUI/UIKit file not in
/// the generator test target). Kept behaviorally identical.
func formatWeight(_ weight: Double) -> String {
    abs(weight.rounded() - weight) < 0.05 ? String(Int(weight.rounded())) : String(format: "%.1f", weight)
}
#endif
