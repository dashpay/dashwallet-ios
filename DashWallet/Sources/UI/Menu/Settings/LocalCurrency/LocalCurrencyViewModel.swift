//
//  Created by Roman Chornyi
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import Combine

// MARK: - CurrencyItem

struct CurrencyItem: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let flagName: String?
    let priceString: String?
}

// MARK: - LocalCurrencyViewModel

@MainActor
class LocalCurrencyViewModel: ObservableObject {
    private let allItems: [CurrencyItem]

    @Published var searchQuery: String = ""
    @Published var selectedCurrencyCode: String

    var filteredItems: [CurrencyItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allItems }
        let query = trimmed.lowercased()
        return allItems.filter {
            $0.code.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
    }

    /// Production init — loads currencies from CurrencyExchangerObjcWrapper.
    init(currencyCode: String? = nil) {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let items: [CurrencyItem] = CurrencyExchangerObjcWrapper.prices.map { price in
            CurrencyItem(
                code: price.code,
                name: price.name,
                flagName: LocalCurrencyViewModel.flagByCode[price.code],
                priceString: formatter.string(from: price.price)
            )
        }
        self.allItems = items
        self.selectedCurrencyCode = currencyCode ?? App.fiatCurrency
    }

    /// Preview / testing init — accepts pre-built items without DashSync.
    init(items: [CurrencyItem], selectedCode: String) {
        self.allItems = items
        self.selectedCurrencyCode = selectedCode
    }

    func select(currencyCode: String) {
        selectedCurrencyCode = currencyCode
        App.shared.fiatCurrency = currencyCode
    }
}

// MARK: - Flag mapping

extension LocalCurrencyViewModel {
    static let flagByCode: [String: String] = [
        "AED": "united arab emirates",
        "AFN": "afghanistan",
        "ALL": "albania",
        "AMD": "armenia",
        "ANG": "sint maarten",
        "AOA": "angola",
        "ARS": "argentina",
        "AUD": "australia",
        "AWG": "aruba",
        "AZN": "azerbaijan",
        "BAM": "bosnia and herzegovina",
        "BBD": "barbados",
        "BDT": "bangladesh",
        "BGN": "bulgaria",
        "BHD": "bahrain",
        "BIF": "burundi",
        "BMD": "bermuda",
        "BND": "brunei",
        "BOB": "bolivia",
        "BRL": "brazil",
        "BSD": "bahamas",
        "BTN": "bhutan",
        "BWP": "botswana",
        "BYN": "belarus",
        "BZD": "belize",
        "CAD": "canada",
        "CDF": "democratic republic of congo",
        "CHF": "switzerland",
        "CLF": "chile",
        "CLP": "chile",
        "CNY": "china",
        "COP": "colombia",
        "CRC": "costa rica",
        "CUP": "cuba",
        "CVE": "cape verde",
        "CZK": "czech republic",
        "DJF": "djibouti",
        "DKK": "denmark",
        "DOP": "dominican republic",
        "DZD": "Algeria",
        "EGP": "egypt",
        "ETB": "ethiopia",
        "EUR": "european union",
        "FJD": "fiji",
        "FKP": "falkland islands",
        "GBP": "united kingdom",
        "GEL": "georgia",
        "GHS": "ghana",
        "GIP": "gibraltar",
        "GMD": "gambia",
        "GNF": "guinea",
        "GTQ": "guatemala",
        "GYD": "guyana",
        "HKD": "hong kong",
        "HNL": "honduras",
        "HRK": "croatia",
        "HTG": "haiti",
        "HUF": "hungary",
        "IDR": "indonesia",
        "ILS": "israel",
        "INR": "india",
        "IQD": "iraq",
        "IRR": "iran",
        "ISK": "iceland",
        "JEP": "jersey",
        "JMD": "jamaica",
        "JOD": "jordan",
        "JPY": "japan",
        "KES": "kenya",
        "KGS": "kyrgyzstan",
        "KHR": "cambodia",
        "KMF": "comoros",
        "KPW": "north korea",
        "KRW": "south korea",
        "KWD": "kuwait",
        "KYD": "cayman islands",
        "KZT": "kazakhstan",
        "LAK": "laos",
        "LBP": "lebanon",
        "LKR": "sri lanka",
        "LRD": "liberia",
        "LSL": "lesotho",
        "LYD": "libya",
        "MAD": "morocco",
        "MDL": "moldova",
        "MGA": "madagascar",
        "MKD": "republic of macedonia",
        "MMK": "myanmar",
        "MNT": "mongolia",
        "MOP": "macao",
        "MRU": "mauritania",
        "MUR": "mauritius",
        "MVR": "maldives",
        "MWK": "malawi",
        "MXN": "mexico",
        "MYR": "malaysia",
        "MZN": "mozambique",
        "NAD": "namibia",
        "NGN": "nigeria",
        "NIO": "nicaragua",
        "NOK": "norway",
        "NPR": "nepal",
        "NZD": "new zealand",
        "OMR": "oman",
        "PAB": "panama",
        "PEN": "peru",
        "PGK": "papua new guinea",
        "PHP": "philippines",
        "PKR": "pakistan",
        "PLN": "poland",
        "PYG": "paraguay",
        "QAR": "qatar",
        "RON": "romania",
        "RSD": "serbia",
        "RUB": "russia",
        "RWF": "rwanda",
        "SAR": "saudi arabia",
        "SBD": "solomon islands",
        "SCR": "seychelles",
        "SDG": "sudan",
        "SEK": "sweden",
        "SGD": "singapore",
        "SHP": "united kingdom",
        "SLL": "sierra leone",
        "SOS": "somalia",
        "SRD": "suriname",
        "STN": "sao tome and prince",
        "SVC": "el salvador",
        "SYP": "syria",
        "SZL": "swaziland",
        "THB": "thailand",
        "TJS": "tajikistan",
        "TMT": "turkmenistan",
        "TND": "tunisia",
        "TOP": "tonga",
        "TRY": "turkey",
        "TTD": "trinidad and tobago",
        "TWD": "taiwan",
        "TZS": "tanzania",
        "UAH": "ukraine",
        "UGX": "uganda",
        "USD": "united states",
        "UYU": "uruguay",
        "UZS": "uzbekistan",
        "VES": "venezuela",
        "VND": "vietnam",
        "VUV": "vanuatu",
        "WST": "samoa",
        "XAF": "central african cfa franc",
        "XCD": "anguilla",
        "XOF": "benin",
        "XPF": "french polynesia",
        "YER": "yemen",
        "ZAR": "south africa",
        "ZMW": "zambia",
        "ZWL": "zimbabwe",
    ]
}
