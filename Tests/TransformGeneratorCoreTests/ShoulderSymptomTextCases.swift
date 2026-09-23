import Foundation

// Shared by XCTest and the Windows Foundation-only executable; no app/model dependency.
enum ShoulderSymptomTextCases {
    static let phrases = ["row", "overhead press", "overhead pressing", "dip", "lateral raise", "face pull"]
    static let examples: [(input: String, expected: String)] = {
        let press = "Right shoulder pain with overhead pressing"
        let row = "Shoulder pain during rows"
        let positive: [(String, String)] = [
            (press + ". No pain on rows.", press),
            ("No pain on rows. " + press + ".", press),
            (press + "; No pain on rows", press),
            (press + "\nNo pain on rows", press),
            (row + ". No pain on rows.", row),
            (row + ". No pain on overhead pressing.", row),
            (press + ". No pain on rows. Shoulder pain on dips.", press + "; Shoulder pain on dips"),
            ("LEFT ANTERIOR SHOULDER PAIN DURING OVERHEAD PRESSING. No pain on rows.",
             "LEFT ANTERIOR SHOULDER PAIN DURING OVERHEAD PRESSING")
        ]
        let unchanged = [
            press + ". No pain on rows, but heavy rows hurt.",
            press + ". No pain on rows anymore, except under load.",
            press + ". No pain on rows?",
            press + "? No pain on rows.",
            press + ". No pain on rows!",
            press + ". No pain on rows; but pain after training.",
            press + ". No pain on rows or dips.",
            press + ". No pain on rows unless heavy.",
            press + ". No pain on rows yet.",
            press + ". No pain on my shoulder.",
            press + ". No pain on unknown movements.",
            "Shoulder impingement. No pain on rows.",
            "No shoulder pain with overhead pressing. No pain on rows.",
            "No pain on rows.",
            press + "; dips are pain free.",
            "Shoulder pain is not present with overhead pressing. No pain on rows.",
            press + ". No pain on rows. However, rows hurt afterwards.",
            "He denied shoulder pain with overhead pressing. No pain on rows.",
            "", press
        ]
        return positive + unchanged.map { ($0, $0) }
    }()
}
