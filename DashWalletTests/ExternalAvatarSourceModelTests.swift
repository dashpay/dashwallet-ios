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

#if DASHPAY
import XCTest
@testable import dashpay

/// The input rules of the Gravatar and public URL avatar sources, carried
/// over from the Objective-C screens they replace.
@MainActor
final class ExternalAvatarSourceModelTests: XCTestCase {
    private typealias Model = ExternalAvatarSourceModel

    func testGravatarURLUsesTheLowercaseMD5OfTheTrimmedEmail() throws {
        let url = try Model.imageURL(for: "  test@example.com \n", kind: .gravatar).get()
        // md5("test@example.com")
        XCTAssertEqual(url.absoluteString, "https://www.gravatar.com/avatar/55502f40dc8b7c769880b10874abc9d0?s=200&d=404")
    }

    func testGravatarRejectsAnInvalidEmail() {
        for input in ["", "abc", "a@b", "a b@c.com"] {
            XCTAssertThrowsError(try Model.imageURL(for: input, kind: .gravatar).get(), input)
        }
    }

    func testPublicURLRejectsEmptyAndTooLongLinks() {
        XCTAssertThrowsError(try Model.imageURL(for: "   ", kind: .publicURL).get())
        let tooLong = "https://example.com/" + String(repeating: "a", count: Model.maxURLLength)
        XCTAssertThrowsError(try Model.imageURL(for: tooLong, kind: .publicURL).get())
        let longest = "https://example.com/" + String(repeating: "a", count: Model.maxURLLength - 20)
        XCTAssertNoThrow(try Model.imageURL(for: longest, kind: .publicURL).get())
    }

    func testGoogleDriveShareLinkBecomesADirectLink() throws {
        let url = try Model.imageURL(
            for: "https://drive.google.com/file/d/12rhWM7_wIXwDcFfsANkVGa0ArrbnhrMN/view?usp=sharing",
            kind: .publicURL).get()
        XCTAssertEqual(url.absoluteString, "https://drive.google.com/uc?export=view&id=12rhWM7_wIXwDcFfsANkVGa0ArrbnhrMN")
    }

    func testDropboxShareLinkBecomesADirectLink() throws {
        let url = try Model.imageURL(
            for: "https://www.dropbox.com/s/2ldd9fjk02yvyv1/IMG_20201103_220114.jpg?dl=0",
            kind: .publicURL).get()
        XCTAssertEqual(url.absoluteString, "https://dl.dropboxusercontent.com/s/2ldd9fjk02yvyv1/IMG_20201103_220114.jpg?dl=0")
    }

    func testOtherLinksAreUsedAsTyped() throws {
        let url = try Model.imageURL(for: "https://example.com/me.png", kind: .publicURL).get()
        XCTAssertEqual(url.absoluteString, "https://example.com/me.png")
    }

    func testOnlyAPublicURLImageIsCropped() {
        XCTAssertFalse(Model.Kind.gravatar.shouldCrop)
        XCTAssertTrue(Model.Kind.publicURL.shouldCrop)
    }
}
#endif
