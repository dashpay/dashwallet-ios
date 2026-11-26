//
//  Created by Dash Core Group
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

@testable import dashpay
import XCTest

@MainActor
final class SetPinViewModelTests: XCTestCase {
    private var savedPins: [String] = []
    private var saveSucceeds = true
    private var setCount = 0
    private var cancelCount = 0

    /// Slides and shakes finish at once.
    private func makeModel() -> SetPinViewModel {
        let model = SetPinViewModel(
            savePin: { [unowned self] pin in
                self.savedPins.append(pin)
                return self.saveSucceeds
            },
            schedule: { _, work in work() }
        )
        model.onSet = { [unowned self] in self.setCount += 1 }
        model.onCancel = { [unowned self] in self.cancelCount += 1 }
        return model
    }

    private func enter(_ digits: String, into model: SetPinViewModel) {
        for character in digits {
            model.enter(digit: character.wholeNumberValue!)
        }
    }

    func testAFullPinMovesOnToConfirmation() {
        let model = makeModel()

        enter("123", into: model)
        XCTAssertEqual(model.step, .set)

        enter("4", into: model)
        XCTAssertEqual(model.step, .confirm)
        XCTAssertEqual(model.pin, "1234")
        XCTAssertEqual(model.confirmation, "")
        XCTAssertTrue(model.isInputEnabled)
    }

    func testAMatchingConfirmationSavesThePin() {
        let model = makeModel()

        enter("1234", into: model)
        enter("1234", into: model)

        XCTAssertEqual(savedPins, ["1234"])
        XCTAssertEqual(setCount, 1)
        XCTAssertEqual(cancelCount, 0)
    }

    func testAMismatchKeepsTheFirstEntryAndClearsTheConfirmation() {
        let model = makeModel()

        enter("1234", into: model)
        enter("4321", into: model)

        XCTAssertEqual(model.rejections, 1)
        XCTAssertEqual(model.step, .confirm)
        XCTAssertEqual(model.pin, "1234")
        XCTAssertEqual(model.confirmation, "")
        XCTAssertTrue(model.isInputEnabled)
        XCTAssertTrue(savedPins.isEmpty)

        enter("1234", into: model)
        XCTAssertEqual(setCount, 1)
    }

    func testCancelOnSetPinLeaves() {
        let model = makeModel()
        enter("12", into: model)

        model.cancel()

        XCTAssertEqual(cancelCount, 1)
    }

    func testCancelOnConfirmPinStartsOver() {
        let model = makeModel()
        enter("1234", into: model)
        enter("12", into: model)

        model.cancel()

        XCTAssertEqual(cancelCount, 0)
        XCTAssertEqual(model.step, .set)
        XCTAssertEqual(model.pin, "")
        XCTAssertEqual(model.confirmation, "")
    }

    func testAPinThatCannotBeSavedNeverReportsSuccess() {
        saveSucceeds = false
        let model = makeModel()

        enter("1234", into: model)
        enter("1234", into: model)

        XCTAssertEqual(setCount, 0)
        XCTAssertEqual(cancelCount, 1)
    }

    func testDeleteRemovesTheLastDigitOfTheCurrentStep() {
        let model = makeModel()
        enter("12", into: model)
        model.deleteBackward()
        XCTAssertEqual(model.pin, "1")

        enter("234", into: model)
        enter("5", into: model)
        model.deleteBackward()
        XCTAssertEqual(model.confirmation, "")
        XCTAssertEqual(model.pin, "1234")
    }
}
