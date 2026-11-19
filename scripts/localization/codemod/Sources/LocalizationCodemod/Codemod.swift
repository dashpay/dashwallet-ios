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
struct Edit {
    let offset: Int
    let length: Int
    let text: String
}

/// Finds `NSLocalizedString` calls; plain `(key, comment:)` calls become edits, the rest become leftovers.
final class LookupVisitor: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private let path: String
    private(set) var edits: [Edit] = []
    private(set) var leftovers: [Leftover] = []
    private let keepLiteralKeys: Set<String>
    private static let unsupportedLabels: Set<String> = ["tableName", "bundle", "value"]

    init(converter: SourceLocationConverter, path: String, keepLiteralKeys: Set<String>) {
        self.converter = converter
        self.path = path
        self.keepLiteralKeys = keepLiteralKeys
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let formatted = formattedLookup(node) {
            return visitFormatted(node, formatted)
        }
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "NSLocalizedString" else { return .visitChildren }
        if let reason = unsupportedReason(node) {
            addLeftover(node, reason)
        } else if let first = node.arguments.first {
            edits.append(Edit(offset: callee.baseName.positionAfterSkippingLeadingTrivia.utf8Offset,
                              length: callee.baseName.text.utf8.count, text: "String"))
            edits.append(Edit(offset: first.expression.positionAfterSkippingLeadingTrivia.utf8Offset,
                              length: 0, text: "localized: "))
        }
        return .visitChildren
    }

    func addEdit(_ edit: Edit) { edits.append(edit) }

    func addLeftover(_ node: FunctionCallExprSyntax, _ reason: String) {
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        leftovers.append(Leftover(path: path, line: line, reason: reason))
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
        if literal.segments.contains(where: { $0.description.contains("%") }),
           !keepLiteralKeys.contains(Self.content(of: literal)) { return "format code in key (T4)" }
        guard args.count == 2, args[1].label?.text == "comment" else { return "unsupported call shape" }
        return nil
    }
}

/// `String(format: NSLocalizedString("key", comment: c), args…)` or the `localizedStringWithFormat` twin.
struct FormattedLookup {
    let literal: StringLiteralExprSyntax
    let comment: LabeledExprSyntax
    let arguments: [LabeledExprSyntax]
}

extension LookupVisitor {
    /// Raw source text between the quotes.
    static func content(of literal: StringLiteralExprSyntax) -> String {
        literal.segments.map(\.description).joined()
    }

    /// Matches only a `(literal key, comment:)` lookup as the format; anything else is not ours (nil).
    fileprivate func formattedLookup(_ node: FunctionCallExprSyntax) -> FormattedLookup? {
        let args = Array(node.arguments)
        guard let first = args.first else { return nil }
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            guard callee.baseName.text == "String", first.label?.text == "format" else { return nil }
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            guard member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "String",
                  member.declName.baseName.text == "localizedStringWithFormat", first.label == nil else { return nil }
        } else {
            return nil
        }
        guard let lookup = first.expression.as(FunctionCallExprSyntax.self),
              lookup.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "NSLocalizedString"
        else { return nil }
        let lookupArgs = Array(lookup.arguments)
        guard lookupArgs.count == 2, lookupArgs[0].label == nil, lookupArgs[1].label?.text == "comment",
              let literal = lookupArgs[0].expression.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) }) else { return nil }
        return FormattedLookup(literal: literal, comment: lookupArgs[1], arguments: Array(args.dropFirst()))
    }

    fileprivate func visitFormatted(_ node: FunctionCallExprSyntax,
                                    _ lookup: FormattedLookup) -> SyntaxVisitorContinueKind {
        let key = Self.content(of: lookup.literal)
        if keepLiteralKeys.contains(key) { return .visitChildren }
        switch formattedRewrite(node, lookup, key: key) {
        case let .success(text):
            let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
            addEdit(Edit(offset: start, length: node.endPositionBeforeTrailingTrivia.utf8Offset - start, text: text))
        case let .failure(reason):
            addLeftover(node, reason.text)
        }
        return .skipChildren
    }

    private func formattedRewrite(_ node: FunctionCallExprSyntax, _ lookup: FormattedLookup,
                                  key: String) -> Result<String, FormatInterpolation.Reason> {
        typealias Reason = FormatInterpolation.Reason
        let literal = lookup.literal
        guard literal.openingPounds == nil, literal.openingQuote.tokenKind == .stringQuote else {
            return .failure(Reason("unsupported key literal"))
        }
        guard node.trailingClosure == nil, lookup.arguments.allSatisfy({ $0.label == nil }) else {
            return .failure(Reason("unsupported call shape"))
        }
        let tokens = Array(node.tokens(viewMode: .sourceAccurate))
        let hasComment = tokens.enumerated().contains { offset, token in
            (offset > 0 && token.leadingTrivia.contains { $0.isComment })
                || (offset < tokens.count - 1 && token.trailingTrivia.contains { $0.isComment })
        }
        if hasComment { return .failure(Reason("comment inside call")) }
        var texts: [String] = []
        for expression in lookup.arguments.map(\.expression) + [lookup.comment.expression] {
            var text = expression.trimmedDescription
            if text.contains("NSLocalizedString") {
                let nested = rewrite(source: text, path: path, keepLiteralKeys: keepLiteralKeys)
                guard nested.leftovers.isEmpty else { return .failure(Reason("nested lookup in argument")) }
                text = nested.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if text.contains("\n") { return .failure(Reason("multi-line argument")) }
            texts.append(text)
        }
        let comment = texts.removeLast()
        return FormatInterpolation.interpolate(key, arguments: texts)
            .map { "String(localized: \"\($0)\", comment: \(comment))" }
    }
}

/// Rewrites plain `NSLocalizedString` lookups in one source text; everything else is listed as a leftover.
public func rewrite(source: String, path: String,
                    keepLiteralKeys: Set<String> = []) -> (output: String, leftovers: [Leftover]) {
    let tree = Parser.parse(source: source)
    let visitor = LookupVisitor(converter: SourceLocationConverter(fileName: path, tree: tree), path: path,
                                keepLiteralKeys: keepLiteralKeys)
    visitor.walk(tree)
    guard !visitor.edits.isEmpty else { return (source, visitor.leftovers) }
    var bytes = Array(source.utf8)
    for edit in visitor.edits.sorted(by: { $0.offset > $1.offset }) {
        bytes.replaceSubrange(edit.offset ..< edit.offset + edit.length, with: Array(edit.text.utf8))
    }
    return (String(bytes: bytes, encoding: .utf8) ?? source, visitor.leftovers)
}

/// Rewrites every in-scope `.swift` file under `roots` (in place unless `dryRun`); returns the sorted leftover lines.
public func runCodemod(roots: [String], dryRun: Bool = false, keepLiteralKeys: Set<String> = []) throws -> [String] {
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
            let result = rewrite(source: source, path: path, keepLiteralKeys: keepLiteralKeys)
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
