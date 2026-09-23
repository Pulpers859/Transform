import Foundation

/// Conservative text preprocessing, not diagnosis or a general negation interpreter.
/// Only a report made entirely of recognized affirmative complaints and standalone
/// "No pain on <movement>" clauses is rewritten. Everything else stays byte-for-byte.
enum ShoulderSymptomText {
    private static let complaint = try? NSRegularExpression(
        pattern: #"^(?:(?:left|right|anterior|posterior) )*shoulder pain (?:with|during|on) (.+)$"#)

    static func movementMatchingText(_ report: String, movementPhrases: [String]) -> String {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased().replacingOccurrences(of: "-", with: " ")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        let phrases = Set(movementPhrases.map(normalized).filter { !$0.isEmpty })
        func isMovement(_ text: String) -> Bool {
            phrases.contains(text) || phrases.contains { text == $0 + "s" || text == $0 + "es" }
        }
        let clauses = report.components(separatedBy: CharacterSet(charactersIn: ".;\n\r"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard clauses.count > 1 else { return report }
        guard let expression = complaint else { return report }
        var affirmative: [String] = []
        var removed = false
        for clause in clauses {
            let text = normalized(clause)
            let prefix = "no pain on "
            if text.hasPrefix(prefix), isMovement(String(text.dropFirst(prefix.count))) {
                removed = true
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                  let movementRange = Range(match.range(at: 1), in: text),
                  isMovement(String(text[movementRange])) else { return report }
            affirmative.append(clause)
        }
        // A contradictory affirmative complaint survives; a denial alone cannot clear caution.
        guard removed, !affirmative.isEmpty else { return report }
        return affirmative.joined(separator: "; ")
    }
}
