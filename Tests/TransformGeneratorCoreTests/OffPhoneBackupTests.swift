import XCTest
@testable import Transform

/// Review of 2026-11-21: every automatic backup lived on the phone with the data. The
/// off-phone copy's rules decide when it writes, what it may delete, and what it reports.
final class OffPhoneBackupTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = Date(timeIntervalSince1970: 2_000_000_000) // 2033-05-18 03:33:20 UTC

    func testCopiesWhenNeverCopiedOrIntervalPassed() {
        XCTAssertTrue(OffPhoneBackupPolicy.isDue(lastCopy: nil, now: now))
        XCTAssertFalse(OffPhoneBackupPolicy.isDue(lastCopy: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(OffPhoneBackupPolicy.isDue(lastCopy: now.addingTimeInterval(-OffPhoneBackupPolicy.minimumInterval), now: now))
    }

    func testAFutureStampDoesNotBlockCopiesForever() {
        XCTAssertTrue(OffPhoneBackupPolicy.isDue(lastCopy: now.addingTimeInterval(86_400), now: now))
    }

    /// Audit 2026-11-21 (L3): names must not follow the phone's calendar setting, or a
    /// Japanese-calendar year ("0008") would sort below every older file and be pruned.
    func testFileNamesUseTheGregorianYearWhateverThePhonesCalendar() {
        XCTAssertTrue(OffPhoneBackupPolicy.fileName(for: now, calendar: Calendar(identifier: .japanese))
            .hasPrefix("Transform_Backup_2033-"))
    }

    func testOneFilePerDay() {
        XCTAssertEqual(OffPhoneBackupPolicy.fileName(for: now, calendar: calendar), "Transform_Backup_2033-05-18.json")
        XCTAssertTrue(OffPhoneBackupPolicy.isOwnBackupName("Transform_Backup_2033-05-18.json"))
    }

    func testOnlyOwnFilesAreEverPruned() {
        let own = (1...9).map { "Transform_Backup_2033-05-0\($0).json" }
        let others = ["Transform_AutoBackup.json", "Transform_Backup_notes.json", "Transform_Backup_2033-5-1.json",
                      "taxes.pdf", "Transform_Backup_2033-05-01.json.bak"]
        let pruned = OffPhoneBackupPolicy.namesToPrune((own + others).shuffled())
        XCTAssertEqual(Set(pruned), ["Transform_Backup_2033-05-01.json", "Transform_Backup_2033-05-02.json"])
        XCTAssertTrue(OffPhoneBackupPolicy.namesToPrune(Array(own.prefix(OffPhoneBackupPolicy.keepCount))).isEmpty)
    }

    func testStatusReportsPhoneOnlyWhenNoFolder() {
        let status = OffPhoneBackupPolicy.status(hasFolder: false, lastSuccess: now, lastFailure: nil,
                                                 failureReason: nil, now: now, calendar: calendar)
        XCTAssertEqual(status, .noFolder)
        XCTAssertTrue(status.needsAttention)
    }

    func testStatusAgesAndGoesStale() {
        func status(daysAgo: Double) -> OffPhoneBackupPolicy.Status {
            OffPhoneBackupPolicy.status(hasFolder: true, lastSuccess: now.addingTimeInterval(-daysAgo * 86_400),
                                        lastFailure: nil, failureReason: nil, now: now, calendar: calendar)
        }
        XCTAssertEqual(status(daysAgo: 0), .current(daysAgo: 0))
        XCTAssertFalse(status(daysAgo: 0).needsAttention)
        XCTAssertEqual(status(daysAgo: 2), .current(daysAgo: 2))
        XCTAssertEqual(status(daysAgo: 3), .stale(daysAgo: 3))
        XCTAssertTrue(status(daysAgo: 3).needsAttention)
    }

    func testANewerFailureIsReportedNotHidden() {
        let status = OffPhoneBackupPolicy.status(hasFolder: true, lastSuccess: now.addingTimeInterval(-86_400),
                                                 lastFailure: now, failureReason: "No permission", now: now, calendar: calendar)
        XCTAssertEqual(status, .failing(reason: "No permission", lastSuccessDaysAgo: 1))
        let recovered = OffPhoneBackupPolicy.status(hasFolder: true, lastSuccess: now, lastFailure: now.addingTimeInterval(-60),
                                                    failureReason: "No permission", now: now, calendar: calendar)
        XCTAssertEqual(recovered, .current(daysAgo: 0))
    }
}
