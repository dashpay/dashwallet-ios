import Foundation

/// Turns the text of a printf-style key into the text of a Swift string literal with interpolations.
enum FormatInterpolation {
    private enum Part {
        case text(String)
        case argument(Int)
    }

    private static let modifierCharacters = Set("-+ #.0123456789*'")
    private static let lengthCharacters = Set("lhzqjtL")
    private static let floatCodes = Set("fFeEgGaA")
    private static let objectAndIntegerCodes = Set("@diu")

    /// `content` is the raw source text between the quotes (escapes kept as written).
    /// Returns the new literal text, or the leftover reason.
    static func interpolate(_ content: String, arguments: [String]) -> Result<String, Reason> {
        let parts: [Part]
        switch parse(content) {
        case let .success(parsed): parts = parsed
        case let .failure(reason): return .failure(reason)
        }
        let indices = parts.compactMap { part -> Int? in
            if case let .argument(index) = part { return index }
            return nil
        }
        guard indices.sorted() == Array(0 ..< arguments.count) else { return .failure(Reason("argument mismatch")) }
        var text = ""
        for part in parts {
            switch part {
            case let .text(string): text += string
            case let .argument(index): text += "\\(" + arguments[index] + ")"
            }
        }
        return .success(text)
    }

    struct Reason: Error, Equatable {
        let text: String

        init(_ text: String) { self.text = text }
    }

    private static func parse(_ content: String) -> Result<[Part], Reason> {
        let chars = Array(content)
        var parts: [Part] = []
        var text = ""
        var sequential = 0
        var usedPositional = false
        var usedSequential = false
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\\" {
                text.append(contentsOf: chars[index ..< min(index + 2, chars.count)])
                index += 2
                continue
            }
            guard char == "%" else {
                text.append(char)
                index += 1
                continue
            }
            index += 1
            if index < chars.count, chars[index] == "%" {
                text.append("%")
                index += 1
                continue
            }
            let position = positionPrefix(chars, &index)
            switch conversion(chars, &index) {
            case let .failure(reason): return .failure(reason)
            case .success: break
            }
            if let position {
                usedPositional = true
                parts.append(.text(text))
                parts.append(.argument(position - 1))
            } else {
                usedSequential = true
                parts.append(.text(text))
                parts.append(.argument(sequential))
                sequential += 1
            }
            text = ""
            if usedPositional && usedSequential { return .failure(Reason("argument mismatch")) }
        }
        parts.append(.text(text))
        return .success(parts)
    }

    /// Consumes `<n>$` when present and returns n.
    private static func positionPrefix(_ chars: [Character], _ index: inout Int) -> Int? {
        var end = index
        while end < chars.count, chars[end].isASCII, chars[end].isNumber { end += 1 }
        guard end > index, end < chars.count, chars[end] == "$", let number = Int(String(chars[index ..< end])),
              number > 0 else { return nil }
        index = end + 1
        return number
    }

    /// Consumes flags, width, precision, length and the conversion; succeeds only for `%@ %d %i %u` (any length).
    private static func conversion(_ chars: [Character], _ index: inout Int) -> Result<Void, Reason> {
        var modifiers = ""
        while index < chars.count, modifierCharacters.contains(chars[index]) {
            modifiers.append(chars[index])
            index += 1
        }
        while index < chars.count, lengthCharacters.contains(chars[index]) { index += 1 }
        guard index < chars.count else { return .failure(Reason("unsupported format specifier")) }
        let code = chars[index]
        index += 1
        if floatCodes.contains(code) {
            return .failure(Reason(modifiers.contains(".") ? "fixed-precision float" : "float format"))
        }
        guard objectAndIntegerCodes.contains(code), modifiers.isEmpty else {
            return .failure(Reason("unsupported format specifier"))
        }
        return .success(())
    }
}
