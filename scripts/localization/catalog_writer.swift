// Serializes a JSON file the way the Xcode app writes a String Catalog.
// Usage: catalog_writer <in.json> <out.xcstrings>
// Two-space indent, " : " separator, keys of every object in localizedStandardCompare order
// (pinned to the en_US locale so the order does not depend on the Mac's language),
// empty object as "{\n\n<indent>}", only ", \ and control characters escaped, no trailing newline.
import Foundation

func escape(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 {
                out += String(format: "\\u%04x", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out + "\""
}

let enUS = Locale(identifier: "en_US")
let standardOptions: String.CompareOptions = [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering]

func isOrderedBefore(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: standardOptions, range: nil, locale: enUS) == .orderedAscending
}

func serialize(_ value: Any, _ indent: String) -> String {
    let inner = indent + "  "
    if let dict = value as? [String: Any] {
        if dict.isEmpty { return "{\n\n" + indent + "}" }
        let keys = dict.keys.sorted(by: isOrderedBefore)
        let members = keys.map { inner + escape($0) + " : " + serialize(dict[$0]!, inner) }
        return "{\n" + members.joined(separator: ",\n") + "\n" + indent + "}"
    }
    if let array = value as? [Any] {
        if array.isEmpty { return "[\n\n" + indent + "]" }
        let items = array.map { inner + serialize($0, inner) }
        return "[\n" + items.joined(separator: ",\n") + "\n" + indent + "]"
    }
    if let string = value as? String { return escape(string) }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        return number.stringValue
    }
    FileHandle.standardError.write("catalog_writer: unsupported JSON value\n".data(using: .utf8)!)
    exit(2)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: catalog_writer <in.json> <out.xcstrings>\n".data(using: .utf8)!)
    exit(2)
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let object = try JSONSerialization.jsonObject(with: data)
    try serialize(object, "").write(toFile: args[2], atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write("catalog_writer: \(error)\n".data(using: .utf8)!)
    exit(1)
}
