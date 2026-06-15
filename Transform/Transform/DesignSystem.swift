import SwiftUI

// MARK: - Type Scale

enum TFTypography {
    static let heroMetric = Font.system(size: 44, weight: .black, design: .rounded)
    static let heroTitle = Font.system(size: 36, weight: .black)
    static let sectionTitle = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 10, weight: .medium)

    static let ringValue = Font.system(size: 22, weight: .black, design: .rounded)
    static let ringUnit = Font.system(size: 10, weight: .medium)
    static let greeting = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let badgeLabel = Font.system(size: 9, weight: .bold)
    static let chipLabel = Font.system(size: 12, weight: .semibold)
    static let datePill = Font.system(size: 11, weight: .semibold, design: .monospaced)
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
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.blue
    static let protein = Color.red
    static let carbs = Color.blue
    static let fat = Color.yellow
    static let sleep = Color.blue
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
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension * UIScreen.main.scale
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
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
