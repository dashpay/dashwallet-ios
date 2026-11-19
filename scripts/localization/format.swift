import Foundation

// Formats lookup keys the way a phone does, for many locales in one process.
// Usage: format <lproj-root>; reads JSON lines {locale, key, args|null} on stdin and writes
// JSON lines {locale, key, args, text} on stdout. Each request is formatted with
// String(format:locale:arguments:) under its own locale; the process locale decides nothing.
// FORMATTER_FORCE_ROUTE=localizedStringWithFormat formats under Locale.current instead.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: format <lproj-root>\n".utf8))
    exit(64)
}

let root = CommandLine.arguments[1]
let wrongRoute = ProcessInfo.processInfo.environment["FORMATTER_FORCE_ROUTE"] == "localizedStringWithFormat"

var bundles: [String: Bundle] = [:]

func bundle(_ locale: String) -> Bundle? {
    if let cached = bundles[locale] { return cached }
    let loaded = Bundle(path: "\(root)/\(locale).lproj")
    bundles[locale] = loaded
    return loaded
}

// Returns the format as a phone would look it up: the key itself when the table lacks it.
func lookup(_ locale: String, _ key: String) -> String {
    bundle(locale)?.localizedString(forKey: key, value: key, table: nil) ?? key
}

// Sample arguments from the format codes of `format`: one distinct value per position.
func inferArgs(_ format: String) -> [Any] {
    // %[n$][flags][width][.precision][length]conversion; %% and %#@var@ are not arguments.
    let pattern = "%(?:(\\d+)\\$)?[-+ 0#']*(?:\\d+|\\*)?(?:\\.\\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUfFeEgGxXoOcCsSp])"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = format as NSString
    var sequential = 0
    var byPosition: [Int: Any] = [:]
    for match in regex.matches(in: format, range: NSRange(location: 0, length: ns.length)) {
        sequential += 1
        var position = sequential
        if match.range(at: 1).location != NSNotFound, let explicit = Int(ns.substring(with: match.range(at: 1))) {
            position = explicit
        }
        let code = ns.substring(with: match.range(at: 3))
        switch code {
        case "@", "s", "S": byPosition[position] = "‹a\(position)›"
        case "f", "F", "e", "E", "g", "G": byPosition[position] = Double(1000 + position) + 0.5
        default: byPosition[position] = 1000 + position
        }
    }
    guard let last = byPosition.keys.max() else { return [] }
    return (1...last).map { byPosition[$0] ?? "‹a\($0)›" }
}

func cVarArgs(_ args: [Any]) -> [CVarArg] {
    args.map { arg -> CVarArg in
        if let number = arg as? NSNumber {
            return CFNumberIsFloatType(number) ? number.doubleValue : number.intValue
        }
        return (arg as? String ?? "\(arg)") as NSString
    }
}

func jsonValue(_ args: [Any]) -> [Any] {
    args.map { arg -> Any in
        if let number = arg as? NSNumber, !CFNumberIsFloatType(number) { return number.intValue }
        return arg
    }
}

func emit(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let locale = request["locale"] as? String, let key = request["key"] as? String else {
        FileHandle.standardError.write(Data("bad request line: \(line)\n".utf8))
        exit(65)
    }
    let args = (request["args"] as? [Any]) ?? inferArgs(lookup("en", key))
    let format = lookup(locale, key)
    let formatLocale = wrongRoute ? Locale.current : Locale(identifier: locale)
    let text = String(format: format, locale: formatLocale, arguments: cVarArgs(args))
    emit(["locale": locale, "key": key, "args": jsonValue(args), "text": text])
}
