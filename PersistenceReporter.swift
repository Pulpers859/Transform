import Foundation
import SwiftData

extension Notification.Name {
    static let persistenceSaveFailed = Notification.Name("transform.persistenceSaveFailed")
}

enum PersistenceReporter {
    static let messageUserInfoKey = "message"

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
}
