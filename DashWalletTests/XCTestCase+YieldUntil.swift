//
//  XCTestCase+YieldUntil.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import XCTest

extension XCTestCase {
    /// Yields until `condition` holds, and fails instead of spinning forever
    /// when it never does (an attempt that stops at a gate never casts).
    @MainActor
    func yield(
        until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
        if !condition() { XCTFail("gave up waiting", file: file, line: line) }
    }
}
