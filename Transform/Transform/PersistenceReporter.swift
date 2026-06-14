import Foundation
import SwiftData
import UIKit

extension Notification.Name {
    static let persistenceSaveFailed = Notification.Name("transform.persistenceSaveFailed")
}

enum PersistenceReporter {
    static let messageUserInfoKey = "message"

    @MainActor
    @discardableResult
    static func save(_ modelContext: ModelContext, operation: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            let message = "Could not save \(operation). Error: \(error.localizedDescription)"
            print("[Persistence] \(message)")
            NotificationCenter.default.post(
                name: .persistenceSaveFailed,
                object: nil,
                userInfo: [messageUserInfoKey: message]
            )
            return false
        }
    }

    @MainActor
    @discardableResult
    static func saveWithBackup(
        _ modelContext: ModelContext,
        operation: String,
        haptic: UINotificationFeedbackGenerator.FeedbackType = .success
    ) -> Bool {
        guard save(modelContext, operation: operation) else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        switch haptic {
        case .success, .warning:
            UINotificationFeedbackGenerator().notificationOccurred(haptic)
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        return true
    }
}
