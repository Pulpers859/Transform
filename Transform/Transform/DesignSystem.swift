import SwiftUI
import UIKit

// MARK: - Haptics

/// Centralized haptic feedback. Keeps intensity choices consistent across the
/// app and provides one place to tune — or globally disable — feedback later.
enum TFHaptics {
    /// A physical "tap" impact. Use for confirmations and lightweight actions.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A semantic notification (success / warning / error).
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// A selection tick. Use when moving between discrete values (pickers, steppers).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }
}

// MARK: - Pressable Button Style

/// Adds a tactile spring press-scale to custom buttons so they feel responsive,
/// matching the feedback the system's own button styles provide. Respects the
/// Reduce Motion accessibility setting.
struct TFPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension View {
    /// Applies the standard Transform press-scale interaction to a button.
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(TFPressableButtonStyle(scale: scale))
    }
}

// MARK: - Type Scale

enum TFTypography {
    /// Scales a design size with the user's Dynamic Type setting, anchored to a
    /// system text style and capped at 1.35× so the dense metric layouts grow
    /// legibly instead of breaking. Computed per access (not cached in a `let`)
    /// so a text-size change re-resolves on the next render pass.
    private static func scaled(
        _ size: CGFloat,
        relativeTo style: UIFont.TextStyle,
        weight: Font.Weight,
        design: Font.Design = .default
    ) -> Font {
        let scaledSize = min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * 1.35)
        return Font.system(size: scaledSize, weight: weight, design: design)
    }

    static var heroMetric: Font { scaled(44, relativeTo: .largeTitle, weight: .black, design: .rounded) }
    static var heroTitle: Font { scaled(36, relativeTo: .largeTitle, weight: .black) }
    static var sectionTitle: Font { scaled(10, relativeTo: .caption2, weight: .bold, design: .monospaced) }
    static var cardTitle: Font { scaled(15, relativeTo: .subheadline, weight: .semibold) }
    static var body: Font { scaled(14, relativeTo: .body, weight: .regular) }
    static var caption: Font { scaled(12, relativeTo: .caption1, weight: .medium) }
    static var micro: Font { scaled(10, relativeTo: .caption2, weight: .medium) }

    static var ringValue: Font { scaled(22, relativeTo: .title2, weight: .black, design: .rounded) }
    static var ringUnit: Font { scaled(10, relativeTo: .caption2, weight: .medium) }
    static var greeting: Font { scaled(13, relativeTo: .footnote, weight: .medium, design: .monospaced) }
    static var badgeLabel: Font { scaled(9, relativeTo: .caption2, weight: .bold) }
    static var chipLabel: Font { scaled(12, relativeTo: .caption1, weight: .semibold) }
    static var datePill: Font { scaled(11, relativeTo: .caption1, weight: .semibold, design: .monospaced) }
}

// MARK: - Color Tokens

enum TFColor {
    static let accent = Color.orange
    static let accentWarm = Color(red: 1.0, green: 0.72, blue: 0.27)
    static let surface = Color(.secondarySystemBackground)
    static let surfaceElevated = Color(.tertiarySystemBackground)
    static let heroGradientTop = Color.black.opacity(0.92)
    static let heroGradientBottom = Color(.systemBackground)
    static let success = Color.green
    static let warning = Color(red: 0.95, green: 0.75, blue: 0.15)
    static let danger = Color.red
    static let info = Color.blue
    // Macro trio: deliberately distinct in hue AND luminance (crimson / blue /
    // amber) so 10pt rings stay separable for red-green colorblindness, and so
    // protein no longer shares pure red with `danger` (which sits inches away
    // on the dashboard meaning "over target").
    static let protein = Color(red: 0.80, green: 0.16, blue: 0.32)
    static let carbs = Color(red: 0.20, green: 0.48, blue: 0.97)
    static let fat = Color(red: 0.98, green: 0.71, blue: 0.15)
    static let sleep = Color(red: 0.38, green: 0.35, blue: 0.82)
    static let measurement = Color.purple
}

// MARK: - Spacing

enum TFSpacing {
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 16
    static let sectionGap: CGFloat = 24
    static let horizontalMargin: CGFloat = 16
    static let innerGap: CGFloat = 12
    static let tightGap: CGFloat = 8
    static let microGap: CGFloat = 4
}

// MARK: - Radii

/// Minimum interactive dimension.
///
/// Apple's HIG floor is 44×44pt. Several controls in this app were sized by their icon
/// instead — a 12pt caret, an 8pt help glyph — which is workable on a desk and not workable
/// mid-set with chalk on your hands. Icons stay small; the TARGET around them does not.
///
/// Use with `.frame(minWidth:minHeight:)` plus `.contentShape(Rectangle())`, since a frame
/// alone widens layout without widening the hit region.
enum TFTapTarget {
    static let minimum: CGFloat = 44
}

enum TFRadius {
    static let card: CGFloat = 16
    static let cardCompact: CGFloat = 12
    static let badge: CGFloat = 99
    static let inner: CGFloat = 8
}

// MARK: - Section Label

struct TFSectionLabel: View {
    let text: String
    var color: Color = TFColor.accent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text.uppercased())
                .font(TFTypography.sectionTitle)
                .foregroundStyle(color)
                .tracking(1.5)
        }
    }
}

// MARK: - Card Entrance Animation

struct CardEntrance: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            .scaleEffect(appeared ? 1 : 0.97)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(index) * 0.08)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    func cardEntrance(index: Int) -> some View {
        modifier(CardEntrance(index: index))
    }
}

// MARK: - Image Downsampling

extension UIImage {
    static func downsampledImage(from data: Data, maxDimension: CGFloat) -> UIImage? {
        // UIScreen.main is deprecated in iOS 26. Use the current trait collection's
        // display scale; fall back to 2x when read off the main thread (where the
        // current traits are unavailable), which is fine for thumbnail sizing.
        let displayScale = UITraitCollection.current.displayScale
        let scale = displayScale > 0 ? displayScale : 2.0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension * scale
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Weight Formatting

func formatWeight(_ weight: Double) -> String {
    abs(weight.rounded() - weight) < 0.05 ? String(Int(weight.rounded())) : String(format: "%.1f", weight)
}

// MARK: - Empty State Template

struct TFEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    var tint: Color = TFColor.accent

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 32)

            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(tint.opacity(0.5))
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))

            VStack(spacing: 8) {
                Text(title)
                    .font(TFTypography.cardTitle)
                    .fontWeight(.bold)
                Text(message)
                    .font(TFTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(TFTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(tint)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }

            Spacer().frame(height: 24)
        }
    }
}
