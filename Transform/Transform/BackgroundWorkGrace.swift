import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Asks iOS for its short background grace period while a paid AI call is in flight
/// (week generation, body analysis), and hands it back as soon as the work ends.
///
/// Without it the app is suspended within seconds of the phone locking or the owner
/// switching apps. A call cut off that way can still be billed by Anthropic, the result
/// never arrives, and trying again pays a second time. iOS grants only a short window
/// (often around 30 seconds, at the system's discretion), so this covers a quick glance at
/// another app, not a locked phone for the whole generation; the in-progress text that
/// asks the owner to keep Transform open is the main protection. Not covered by a test:
/// UIKit lifecycle behaviour.
@MainActor
final class BackgroundWorkGrace {
    #if canImport(UIKit)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(name: String) {
        #if canImport(UIKit)
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Called when the grace period runs out: the task MUST be ended here or iOS
            // terminates the app.
            self?.end()
        }
        #endif
    }

    /// Safe to call more than once.
    func end() {
        #if canImport(UIKit)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}
