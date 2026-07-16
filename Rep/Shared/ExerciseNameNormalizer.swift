import Foundation

enum ExerciseNameNormalizer {
    static func normalize(_ name: String) -> String {
        let folded = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let punctuationAsSpaces = String(folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        })
        return punctuationAsSpaces
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}
