//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

@objc
class DWDateFormatter: NSObject {
    @objc
    static let sharedInstance = DWDateFormatter()

    private let shortDateFormatter: DateFormatter
    private let longDateFormatter: DateFormatter
    private let iso8601DateFormatter: DateFormatter
    private let timeOnlyFormatter: DateFormatter

    private override init() {
        let locale = Locale.current

        shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd MMMM", options: 0, locale: locale)

        longDateFormatter = DateFormatter()
        longDateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd MMMM, yyyy", options: 0, locale: locale)

        iso8601DateFormatter = DateFormatter()
        let enUSPOSIXLocale = Locale(identifier: "en_US_POSIX")
        iso8601DateFormatter.locale = enUSPOSIXLocale
        iso8601DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        iso8601DateFormatter.calendar = Calendar(identifier: .gregorian)
        
        timeOnlyFormatter = DateFormatter()
        timeOnlyFormatter.timeStyle = .short
        timeOnlyFormatter.dateStyle = .none
        timeOnlyFormatter.locale = Locale.current
    }

    func dateOnly(from date: Date) -> String {
        let calendar = Calendar.current
        let nowYear = calendar.component(.year, from: Date())
        let dateYear = calendar.component(.year, from: date)

        let desiredFormatter = (nowYear == dateYear) ? shortDateFormatter : longDateFormatter
        return desiredFormatter.string(from: date)
    }

    func longString(from date: Date) -> String {
        return longDateFormatter.string(from: date)
    }

    func iso8601String(from date: Date) -> String {
        return iso8601DateFormatter.string(from: date)
    }
    
    func timeOnly(from dateTime: Date) -> String {
        return timeOnlyFormatter.string(from: dateTime)
    }
}

@objc extension DWDateFormatter {
    @objc func shortStringFromDate(_ date: Date) -> String {
        return dateOnly(from: date)
    }
}
