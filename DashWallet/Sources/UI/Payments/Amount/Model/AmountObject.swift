//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

// MARK: - AmountObject

struct AmountObject: Equatable {
    let amountType: AmountType
    let amountInternalRepresentation: String
    let inputLocale: Locale

    let plainAmount: UInt64
    let mainFormatted: String

    let supplementaryAmount: Decimal
    let supplementaryFormatted: String

    let localFormatter: NumberFormatter
    let fiatCurrencyCode: String

    init(dashAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter, currencyExchanger: CurrencyExchanger, inputLocale: Locale = .current) {
        var dashAmountString = dashAmountString

        if dashAmountString.isEmpty {
            dashAmountString = "0"
        }

        amountType = .main
        amountInternalRepresentation = dashAmountString
        self.inputLocale = inputLocale
        self.fiatCurrencyCode = fiatCurrencyCode
        self.localFormatter = localFormatter

        let dashNumber = Decimal(string: dashAmountString, locale: inputLocale)!
        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber

        self.plainAmount = NSDecimalNumber(decimal: plainAmount.whole).uint64Value

        let dashFormatter = NumberFormatter.dashFormatter.copy() as! NumberFormatter
        dashFormatter.locale = inputLocale
        mainFormatted = dashFormatter
            .inputString(from: dashNumber as NSNumber, and: dashAmountString, locale: inputLocale) ??
            NSLocalizedString("Invalid Input", comment: "Invalid Amount Input")

        if plainAmount == 0 {
            supplementaryAmount = 0
            supplementaryFormatted = localFormatter.string(from: 0.0)!
        } else if let localAmount = try? currencyExchanger.convertDash(amount: dashNumber, to: fiatCurrencyCode),
                  let str = localFormatter.string(from: localAmount as NSNumber) {
            supplementaryAmount = localAmount
            supplementaryFormatted = str
        } else {
            supplementaryAmount = 0
            supplementaryFormatted = NSLocalizedString("Updating Price", comment: "Updating Price")
        }
    }

    init?(localAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter, currencyExchanger: CurrencyExchanger, inputLocale: Locale = .current) {
        var localAmountString = localAmountString

        if localAmountString.isEmpty {
            localAmountString = "0"
        }

        amountType = .supplementary
        amountInternalRepresentation = localAmountString
        self.inputLocale = inputLocale
        self.fiatCurrencyCode = fiatCurrencyCode
        self.localFormatter = localFormatter

        let localNumber = Decimal(string: localAmountString, locale: inputLocale)!
        let localCurrencyFormatted = localFormatter.inputString(from: localNumber as NSNumber, and: localAmountString, locale: inputLocale)!
        supplementaryFormatted = localCurrencyFormatted
        supplementaryAmount = localNumber

        if localNumber.isZero {
            plainAmount = 0
            let dashFormatter = NumberFormatter.dashFormatter.copy() as! NumberFormatter
            dashFormatter.locale = inputLocale
            mainFormatted = dashFormatter.string(from: 0)!
        } else if let dashAmount = try? currencyExchanger.convertToDash(amount: localNumber, currency: fiatCurrencyCode),
                  let str = {
                      let dashFormatter = NumberFormatter.dashFormatter.copy() as! NumberFormatter
                      dashFormatter.locale = inputLocale
                      return dashFormatter.string(from: dashAmount as NSNumber)
                  }() {
            plainAmount = dashAmount.plainDashAmount
            mainFormatted = str
        } else {
            plainAmount = 0
            mainFormatted = NSLocalizedString("Updating Price", comment: "Updating Price")
        }
    }

    init(plainAmount: UInt64, fiatCurrencyCode: String, localFormatter: NumberFormatter, currencyExchanger: CurrencyExchanger, inputLocale: Locale = .current) {
        let plainNumber = Decimal(plainAmount)
        let duffsNumber = Decimal(DUFFS)
        let dashNumber = plainNumber/duffsNumber
        let dashAmounString = Self.dashInputString(from: dashNumber, locale: inputLocale)

        self.init(dashAmountString: dashAmounString, fiatCurrencyCode: fiatCurrencyCode, localFormatter: localFormatter, currencyExchanger: currencyExchanger, inputLocale: inputLocale)
    }
}

extension AmountObject {
    var dashAmount: AmountObject {
        if amountType == .main { return self }

        let dashNumber = Decimal(plainAmount) / Decimal(DUFFS)
        let amountInternalRepresentation = Self.dashInputString(from: dashNumber, locale: inputLocale)

        return AmountObject(amountInternalRepresentation: amountInternalRepresentation,
                            plainAmount: plainAmount,
                            supplementaryAmount: supplementaryAmount,
                            amountType: .main,
                            mainFormatted: mainFormatted,
                            supplementaryFormatted: supplementaryFormatted,
                            localFormatter: localFormatter,
                            fiatCurrencyCode: fiatCurrencyCode,
                            inputLocale: inputLocale)
    }

    var localAmount: AmountObject {
        if amountType == .supplementary { return self }

        let numberFormatter = localFormatter.copy() as! NumberFormatter
        numberFormatter.numberStyle = .none
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = localFormatter.maximumFractionDigits

        guard let amountInternalRepresentation = numberFormatter.string(from: supplementaryAmount as NSDecimalNumber) else {
            fatalError("Can't convert dash amount: \(plainAmount.formattedDashAmount) to local amount. Supplementary Amount = \(String(describing: supplementaryAmount))")
        }

        guard let formatterAmount = localFormatter.inputString(from: supplementaryAmount as NSNumber, and: amountInternalRepresentation, locale: inputLocale) else {
            fatalError("Can't convert dash amount: \(plainAmount.formattedDashAmount) to local amount. Supplementary Amount = \(String(describing: supplementaryAmount))")
        }

        return AmountObject(amountInternalRepresentation: amountInternalRepresentation,
                            plainAmount: plainAmount,
                            supplementaryAmount: supplementaryAmount,
                            amountType: .supplementary,
                            mainFormatted: mainFormatted,
                            supplementaryFormatted: formatterAmount,
                            localFormatter: localFormatter,
                            fiatCurrencyCode: fiatCurrencyCode,
                            inputLocale: inputLocale)
    }

    init(amountInternalRepresentation: String, plainAmount: UInt64, supplementaryAmount: Decimal, amountType: AmountType, mainFormatted: String,
         supplementaryFormatted: String, localFormatter: NumberFormatter, fiatCurrencyCode: String, inputLocale: Locale) {
        self.amountInternalRepresentation = amountInternalRepresentation
        self.plainAmount = plainAmount
        self.supplementaryAmount = supplementaryAmount
        self.amountType = amountType
        self.mainFormatted = mainFormatted
        self.supplementaryFormatted = supplementaryFormatted
        self.localFormatter = localFormatter
        self.fiatCurrencyCode = fiatCurrencyCode
        self.inputLocale = inputLocale
    }

    private static func dashInputString(from amount: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter.dashDecimalFormatter.copy() as! NumberFormatter
        formatter.locale = locale
        return formatter.string(from: amount as NSDecimalNumber)!
    }
}

// MARK: - PastedAmountParser

enum PastedAmountParser {

    struct ParsedAmount {
        let decimalValue: Decimal
        let normalizedString: String
    }

    private enum SeparatorDecision {
        case decimal(index: Int)
        case groupingOnly
    }

    private static let groupingCharacters: Set<Character> = [
        " ",
        "\u{00A0}",
        "\u{202F}",
        "'",
        "’",
    ]

    private static let unsupportedSignCharacters: Set<Character> = [
        "-",
        "+",
        "−",
        "–",
        "—",
        "(",
        ")",
    ]

    private static let decimalParseLocale = Locale(identifier: "en_US_POSIX")

    static func parse(_ string: String, locale: Locale) -> ParsedAmount? {
        let trimmedInput = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let body = trimmedAmountBody(from: trimmedInput) else { return nil }
        guard body.allSatisfy({ isSupportedBodyCharacter($0) }) else { return nil }
        guard body.contains(where: { $0.isASCIIAmountDigit }) else { return nil }

        let characters = Array(body)
        let dotIndices = indices(of: ".", in: characters)
        let commaIndices = indices(of: ",", in: characters)

        let decision: SeparatorDecision?
        if !dotIndices.isEmpty && !commaIndices.isEmpty {
            decision = .decimal(index: max(dotIndices.last!, commaIndices.last!))
        } else if !dotIndices.isEmpty {
            decision = Self.decision(for: ".", indices: dotIndices, body: body, locale: locale)
        } else if !commaIndices.isEmpty {
            decision = Self.decision(for: ",", indices: commaIndices, body: body, locale: locale)
        } else {
            decision = .groupingOnly
        }

        let normalizedString: String

        guard let decision else { return nil }

        switch decision {
        case .decimal(let decimalIndex):
            let decimalCharacterIndex = body.index(body.startIndex, offsetBy: decimalIndex)
            let integerPart = String(body[..<decimalCharacterIndex])
            let fractionPart = String(body[body.index(after: decimalCharacterIndex)...])

            guard isValidGrouping(integerPart) else { return nil }
            guard fractionPart.allSatisfy({ $0.isASCIIAmountDigit }) else { return nil }

            let integerDigits = digitsOnly(integerPart)
            let fractionDigits = digitsOnly(fractionPart)
            normalizedString = fractionDigits.isEmpty
                ? (integerDigits.isEmpty ? "0" : integerDigits)
                : "\(integerDigits.isEmpty ? "0" : integerDigits).\(fractionDigits)"

        case .groupingOnly:
            guard isValidGrouping(body) else { return nil }
            normalizedString = digitsOnly(body)
        }

        guard normalizedString.contains(where: { $0.isASCIIAmountDigit }) else { return nil }
        guard let decimalValue = Decimal(string: normalizedString, locale: decimalParseLocale) else { return nil }

        return ParsedAmount(decimalValue: decimalValue, normalizedString: normalizedString)
    }

    static func editableString(from decimalValue: Decimal, locale: Locale) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 20
        formatter.roundingMode = .down

        return formatter.string(from: decimalValue as NSDecimalNumber)
    }

    private static func decision(for separator: Character, indices: [Int], body: String, locale: Locale) -> SeparatorDecision? {
        guard let singleIndex = indices.first else { return nil }

        if indices.count > 1 {
            return isValidGrouping(body) ? .groupingOnly : nil
        }

        if separator == ".",
           locale.decimalSeparator?.first == ",",
           locale.decimalSeparator?.count == 1,
           isValidGrouping(body) {
            return .groupingOnly
        }

        if locale.decimalSeparator?.first == separator, locale.decimalSeparator?.count == 1 {
            return .decimal(index: singleIndex)
        }

        if locale.groupingSeparator?.first == separator, locale.groupingSeparator?.count == 1, isValidGrouping(body) {
            return .groupingOnly
        }

        if groupingCharacters.contains(separator), isValidGrouping(body) {
            return .groupingOnly
        }

        return .decimal(index: singleIndex)
    }

    private static func trimmedAmountBody(from string: String) -> String? {
        guard !string.isEmpty else { return nil }
        guard !string.contains(where: { unsupportedSignCharacters.contains($0) }) else { return nil }

        let characters = Array(string)
        guard let startIndex = characters.firstIndex(where: { isAllowedBodyCharacter($0) }),
              let endIndex = characters.lastIndex(where: { isAllowedBodyCharacter($0) }),
              startIndex <= endIndex else {
            return nil
        }

        return String(characters[startIndex...endIndex])
    }

    private static func isValidGrouping(_ string: String) -> Bool {
        let separators = groupingSeparatorCharacters
        let segments = string.split(omittingEmptySubsequences: false, whereSeparator: { separators.contains($0) })

        if segments.count == 1 {
            return segments.first?.allSatisfy({ $0.isASCIIAmountDigit }) == true
        }

        guard !segments.contains(where: { $0.isEmpty }) else { return false }
        guard let firstSegment = segments.first, firstSegment.count >= 1, firstSegment.count <= 3 else { return false }

        return segments.dropFirst().allSatisfy { $0.count == 3 }
    }

    private static var groupingSeparatorCharacters: Set<Character> {
        groupingCharacters.union([".", ","])
    }

    private static func digitsOnly(_ string: String) -> String {
        String(string.filter { $0.isASCIIAmountDigit })
    }

    private static func indices(of character: Character, in characters: [Character]) -> [Int] {
        characters.enumerated().compactMap { $0.element == character ? $0.offset : nil }
    }

    private static func isAllowedBodyCharacter(_ character: Character) -> Bool {
        character.isASCIIAmountDigit
            || character == "."
            || character == ","
            || groupingCharacters.contains(character)
    }

    private static func isSupportedBodyCharacter(_ character: Character) -> Bool {
        isAllowedBodyCharacter(character)
    }
}

private extension Character {
    var isASCIIAmountDigit: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }
}
