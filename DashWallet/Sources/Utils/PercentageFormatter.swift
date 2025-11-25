//
//  Created by Claude Code
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

/// Utility for formatting percentage values with smart decimal precision
enum PercentageFormatter {

    /// Format a percentage value with appropriate decimal places
    /// - Parameters:
    ///   - percent: The percentage value (e.g., 0.5 for 0.5%, 10.0 for 10%)
    ///   - includeSign: Whether to include a leading "-" sign (default: false)
    ///   - includePercent: Whether to include the "%" symbol (default: true)
    /// - Returns: Formatted percentage string (e.g., "0.5%", "-10%", "10")
    static func format(percent: Double, includeSign: Bool = false, includePercent: Bool = true) -> String {
        let sign = includeSign ? "-" : ""
        let percentSymbol = includePercent ? "%%" : ""

        // Use 1 decimal place for percentages < 1%, otherwise use whole numbers
        if percent < 1.0 {
            return String(format: "\(sign)%.1f\(percentSymbol)", percent)
        } else {
            return String(format: "\(sign)%.0f\(percentSymbol)", percent)
        }
    }

    /// Format a percentage from basis points with appropriate decimal places
    /// - Parameters:
    ///   - basisPoints: The value in basis points (e.g., 50 = 0.5%, 1000 = 10%)
    ///   - includeSign: Whether to include a leading "-" sign (default: false)
    ///   - includePercent: Whether to include the "%" symbol (default: true)
    /// - Returns: Formatted percentage string (e.g., "0.5%", "-10%", "10")
    static func format(basisPoints: Int, includeSign: Bool = false, includePercent: Bool = true) -> String {
        let percent = Double(basisPoints) / 100.0
        return format(percent: percent, includeSign: includeSign, includePercent: includePercent)
    }
}
