import Foundation

/// A copy of the automatic backup kept OFF the phone, in a folder the owner picks once
/// (for example an iCloud Drive folder) through the Files picker.
///
/// Why (review of 2026-11-21): all three automatic backups lived in the app's own Documents
/// folder, next to the data they protect. Losing the phone, or deleting the app, lost the
/// data and every backup together; the only copy that ever left the phone was a manual
/// export nobody was reminded to make. The Files picker is a system service, so this needs
/// no iCloud entitlement, which a re-signed sideload build cannot be relied on to carry.
///
/// The rules (pure, pinned by OffPhoneBackupTests):
///  * a copy is written at most once per `minimumInterval`, because the automatic backup
///    runs after nearly every save and carries every progress photo;
///  * one file per calendar day, named `Transform_Backup_yyyy-MM-dd.json`, so a bad day can
///    never overwrite an earlier good one;
///  * only files with exactly that name shape are ever pruned, newest `keepCount` kept;
///    anything else in the folder is never touched;
///  * the status the owner sees is the last SUCCESSFUL copy plus the last failure, so a
///    folder that has stopped working is reported, not silently assumed safe.
enum OffPhoneBackupPolicy {
    static let minimumInterval: TimeInterval = 6 * 60 * 60
    static let keepCount = 7
    /// The dashboard turns amber once the newest off-phone copy is this many days old.
    static let staleAfterDays = 3
    static let filePrefix = "Transform_Backup_"
    static let fileSuffix = ".json"

    static func isDue(lastCopy: Date?, now: Date) -> Bool {
        guard let lastCopy else { return true }
        let elapsed = now.timeIntervalSince(lastCopy)
        // A last-copy stamp in the future (clock change) must not block copies forever.
        return elapsed >= minimumInterval || elapsed < 0
    }

    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return filePrefix + text + fileSuffix
    }

    /// Whether a file name is one this feature wrote. Anything else is left alone.
    static func isOwnBackupName(_ name: String) -> Bool {
        guard name.hasPrefix(filePrefix), name.hasSuffix(fileSuffix) else { return false }
        let middle = name.dropFirst(filePrefix.count).dropLast(fileSuffix.count)
        let pieces = middle.split(separator: "-", omittingEmptySubsequences: false)
        return pieces.count == 3
            && pieces.map(\.count) == [4, 2, 2]
            && pieces.allSatisfy { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    /// Which of `names` to delete: own backups beyond the newest `keepCount`. The date in the
    /// name sorts correctly as text.
    static func namesToPrune(_ names: [String]) -> [String] {
        let own = names.filter(isOwnBackupName).sorted(by: >)
        return Array(own.dropFirst(keepCount))
    }

    enum Status: Equatable {
        case noFolder
        case neverCopied
        case current(daysAgo: Int)
        case stale(daysAgo: Int)
        case failing(reason: String, lastSuccessDaysAgo: Int?)

        var needsAttention: Bool {
            switch self {
            case .current: return false
            default: return true
            }
        }

        var chipText: String {
            switch self {
            case .noFolder: return "Backup on phone only"
            case .neverCopied: return "No off-phone backup yet"
            case .current(let days): return days == 0 ? "Backed up today" : "Backup \(days)d ago"
            case .stale(let days): return "Off-phone backup \(days)d ago"
            case .failing: return "Off-phone backup failing"
            }
        }
    }

    /// A failure newer than the last success wins: the folder is not working right now.
    static func status(hasFolder: Bool, lastSuccess: Date?, lastFailure: Date?, failureReason: String?,
                       now: Date, calendar: Calendar = .current) -> Status {
        guard hasFolder else { return .noFolder }
        let days: (Date) -> Int = {
            max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0),
                                           to: calendar.startOfDay(for: now)).day ?? 0)
        }
        if let lastFailure, lastSuccess.map({ lastFailure > $0 }) ?? true {
            return .failing(reason: failureReason ?? "Unknown error", lastSuccessDaysAgo: lastSuccess.map(days))
        }
        guard let lastSuccess else { return .neverCopied }
        let age = days(lastSuccess)
        return age >= staleAfterDays ? .stale(daysAgo: age) : .current(daysAgo: age)
    }
}

/// Writes the off-phone copy. File-system and security-scoped-bookmark work: not covered by a
/// test (the decisions it makes are `OffPhoneBackupPolicy`'s, which are).
@MainActor
final class OffPhoneBackup {
    static let shared = OffPhoneBackup()

    private enum Keys {
        static let bookmark = "transform.offPhoneBackup.folderBookmark"
        static let folderName = "transform.offPhoneBackup.folderName"
        static let lastSuccess = "transform.offPhoneBackup.lastSuccess"
        static let lastFailure = "transform.offPhoneBackup.lastFailure"
        static let failureReason = "transform.offPhoneBackup.failureReason"
    }

    private let defaults = UserDefaults.standard

    var folderName: String? { defaults.string(forKey: Keys.folderName) }
    var hasFolder: Bool { defaults.data(forKey: Keys.bookmark) != nil }

    func status(now: Date = Date()) -> OffPhoneBackupPolicy.Status {
        OffPhoneBackupPolicy.status(
            hasFolder: hasFolder,
            lastSuccess: defaults.object(forKey: Keys.lastSuccess) as? Date,
            lastFailure: defaults.object(forKey: Keys.lastFailure) as? Date,
            failureReason: defaults.string(forKey: Keys.failureReason),
            now: now)
    }

    /// Remembers a folder the owner picked with the Files picker, and writes a first copy at
    /// once so a folder that cannot be written to is reported straight away.
    func chooseFolder(_ url: URL, data: Data?) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Keys.bookmark)
        defaults.set(url.lastPathComponent, forKey: Keys.folderName)
        defaults.removeObject(forKey: Keys.lastSuccess)
        defaults.removeObject(forKey: Keys.lastFailure)
        defaults.removeObject(forKey: Keys.failureReason)
        if let data { copy(data, now: Date(), force: true) }
    }

    func forgetFolder() {
        for key in [Keys.bookmark, Keys.folderName, Keys.lastSuccess, Keys.lastFailure, Keys.failureReason] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Called after every successful automatic backup. Copies only when due.
    func copyIfDue(_ data: Data, now: Date = Date()) {
        guard hasFolder,
              OffPhoneBackupPolicy.isDue(lastCopy: defaults.object(forKey: Keys.lastSuccess) as? Date, now: now)
        else { return }
        copy(data, now: now, force: false)
    }

    private func copy(_ data: Data, now: Date, force: Bool) {
        do {
            try write(data, now: now)
            defaults.set(now, forKey: Keys.lastSuccess)
            defaults.removeObject(forKey: Keys.lastFailure)
            defaults.removeObject(forKey: Keys.failureReason)
        } catch {
            defaults.set(now, forKey: Keys.lastFailure)
            defaults.set(error.localizedDescription, forKey: Keys.failureReason)
            print("[OffPhoneBackup] Copy failed: \(error.localizedDescription)")
        }
    }

    private func write(_ data: Data, now: Date) throws {
        guard let bookmark = defaults.data(forKey: Keys.bookmark) else { return }
        var isStale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        guard folder.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        if isStale, let refreshed = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: Keys.bookmark)
        }

        let target = folder.appendingPathComponent(OffPhoneBackupPolicy.fileName(for: now))
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }

        // Prune only after a successful write, and only this feature's own files.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in OffPhoneBackupPolicy.namesToPrune(names) {
            let old = folder.appendingPathComponent(name)
            NSFileCoordinator().coordinate(writingItemAt: old, options: .forDeleting, error: nil) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
