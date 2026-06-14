import SwiftUI

extension View {
    func dashCard() -> some View {
        self
            .padding(TFSpacing.cardPadding)
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
    }

    func heroCard() -> some View {
        self
            .padding(TFSpacing.cardPadding)
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: TFRadius.card)
                    .strokeBorder(
                        LinearGradient(
                            colors: [TFColor.accent.opacity(0.35), TFColor.accent.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: TFColor.accent.opacity(0.10), radius: 12, y: 6)
    }

    func compactCard() -> some View {
        self
            .padding(TFSpacing.innerGap)
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}
