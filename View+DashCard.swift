import SwiftUI

extension View {
    func dashCard() -> some View {
        self
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
