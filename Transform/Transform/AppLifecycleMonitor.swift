import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AppRuntimePhase: String {
    case active
    case inactive
    case background
    case unknown
}

struct AppLifecycleSnapshot {
    let phase: AppRuntimePhase
    let generation: Int
    let lastTransitionAt: Date
}

final class AppLifecycleMonitor {
    static let shared = AppLifecycleMonitor()

    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []
    private var phase: AppRuntimePhase = .active
    private var generation = 0
    private var lastTransitionAt = Date()

    private init() {
        startObserving()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    @discardableResult
    func start() -> AppLifecycleSnapshot {
        snapshot()
    }

    func snapshot() -> AppLifecycleSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return AppLifecycleSnapshot(
            phase: phase,
            generation: generation,
            lastTransitionAt: lastTransitionAt
        )
    }

    private func startObserving() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.updatePhase(.active)
            }
        )
        observers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.updatePhase(.inactive)
            }
        )
        observers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.updatePhase(.background)
            }
        )
        observers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.updatePhase(.inactive)
            }
        )
        #endif
    }

    private func updatePhase(_ newPhase: AppRuntimePhase) {
        lock.lock()
        defer { lock.unlock() }

        guard phase != newPhase else { return }
        phase = newPhase
        generation += 1
        lastTransitionAt = Date()
    }
}
