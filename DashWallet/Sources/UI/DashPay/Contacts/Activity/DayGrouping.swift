//
//  DayGrouping.swift
//  DashWallet
//
//  Splitting a dated list into day sections, the way the home transaction
//  list does.
//

import Foundation

/// Day sections for any dated list.
///
/// The heading text comes from `DWDateFormatter.dateOnly`, the same call the
/// home transaction list groups on, so "Today" and "Yesterday" read
/// identically wherever a list is split this way.
enum DayGrouping {

    struct Day<Element>: Identifiable {
        /// The heading — "Today", "Yesterday", or the date. Unique per day,
        /// which is what makes it usable as the id.
        let id: String
        /// A date inside this day, for the weekday shown beside the heading.
        let date: Date
        let elements: [Element]
    }

    /// Newest day first, newest element first within each day.
    static func byDay<Element>(
        _ elements: [Element],
        date: (Element) -> Date
    ) -> [Day<Element>] {
        let sorted = elements.sorted { date($0) > date($1) }

        var order: [String] = []
        var byDay: [String: [Element]] = [:]
        for element in sorted {
            let key = DWDateFormatter.sharedInstance.dateOnly(from: date(element))
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(element)
        }
        return order.compactMap { key in
            guard let elements = byDay[key], let first = elements.first else { return nil }
            return Day(id: key, date: date(first), elements: elements)
        }
    }
}
