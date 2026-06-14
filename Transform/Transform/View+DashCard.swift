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
            .background(
                RoundedRectangle(cornerRadius: TFRadius.card)
                    .fill(TFColor.surface)
                    .shadow(color: TFColor.accent.opacity(0.08), radius: 8, y: 4)
            )
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
