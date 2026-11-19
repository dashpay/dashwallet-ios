import Foundation
import SwiftParser
import SwiftSyntax

/// A place the codemod could not rewrite. Printed as `<path>:<line>: <reason>`.
public struct Leftover: Equatable, Sendable {
    public let path: String
    public let line: Int
    public let reason: String

    public init(path: String, line: Int, reason: String) {
        self.path = path
        self.line = line
        self.reason = reason
    }

    public var description: String { "\(path):\(line): \(reason)" }
}

/// A byte-range replacement in the source text.
private struct Edit {
    let offset: Int
    let length: Int
    let text: String
}

/// Finds `NSLocalizedString` calls; plain `(key, comment:)` calls become edits, the rest become leftovers.
private final class LookupVisitor: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private let path: String
    private(set) var edits: [Edit] = []
    private(set) var leftovers: [Leftover] = []
    private static let unsupportedLabels: Set<String> = ["tableName", "bundle", "value"]

    init(converter: SourceLocationConverter, path: String) {
        self.converter = converter
        self.path = path
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "NSLocalizedString" else { return .visitChildren }
        if let reason = unsupportedReason(node) {
            let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
            leftovers.append(Leftover(path: path, line: line, reason: reason))
        } else if let first = node.arguments.first {
            edits.append(Edit(offset: callee.baseName.positionAfterSkippingLeadingTrivia.utf8Offset,
                              length: callee.baseName.text.utf8.count, text: "String"))
            edits.append(Edit(offset: first.expression.positionAfterSkippingLeadingTrivia.utf8Offset,
                              length: 0, text: "localized: "))
        }
        return .visitChildren
    }

    /// Why the call cannot be rewritten here; nil for a plain `(literal key, comment:)` call.
    private func unsupportedReason(_ call: FunctionCallExprSyntax) -> String? {
        let args = Array(call.arguments)
        guard let first = args.first, first.label == nil,
              let literal = first.expression.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) }) else { return "non-literal key" }
        for arg in args.dropFirst() {
            if let label = arg.label?.text, Self.unsupportedLabels.contains(label) {
                return "unsupported argument: \(label):"
            }
        }
        if literal.segments.contains(where: { $0.description.contains("%") }) { return "format code in key (T4)" }
        guard args.count == 2, args[1].label?.text == "comment" else { return "unsupported call shape" }
        return nil
    }
}

/// Rewrites plain `NSLocalizedString` lookups in one source text; everything else is listed as a leftover.
public func rewrite(source: String, path: String) -> (output: String, leftovers: [Leftover]) {
    let tree = Parser.parse(source: source)
    let visitor = LookupVisitor(converter: SourceLocationConverter(fileName: path, tree: tree), path: path)
    visitor.walk(tree)
    guard !visitor.edits.isEmpty else { return (source, visitor.leftovers) }
    var bytes = Array(source.utf8)
    for edit in visitor.edits.sorted(by: { $0.offset > $1.offset }) {
        bytes.replaceSubrange(edit.offset ..< edit.offset + edit.length, with: Array(edit.text.utf8))
    }
    return (String(bytes: bytes, encoding: .utf8) ?? source, visitor.leftovers)
}

/// Rewrites every in-scope `.swift` file under `roots` (in place unless `dryRun`); returns the sorted leftover lines.
public func runCodemod(roots: [String], dryRun: Bool = false) throws -> [String] {
    let fileManager = FileManager.default
    var leftovers: [Leftover] = []
    for root in roots {
        guard let walker = fileManager.enumerator(atPath: root) else { continue }
        for case let relative as String in walker {
            let components = relative.split(separator: "/")
            if components.contains(where: { $0.hasPrefix("WatchApp") || $0 == "Pods" }) {
                walker.skipDescendants()
                continue
            }
            guard relative.hasSuffix(".swift") else { continue }
            let path = (root as NSString).appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let result = rewrite(source: source, path: path)
            leftovers += result.leftovers
            if !dryRun, result.output != source {
                try result.output.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
    return leftovers
        .sorted { ($0.path, $0.line, $0.reason) < ($1.path, $1.line, $1.reason) }
        .map(\.description)
}
