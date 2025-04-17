//  
//  Created by Andrei Ashikhmin
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

class PrivateMemoViewModel: ObservableObject {
    let maxChars = 25
    
    @Published var input: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = "This is some error"
    
    func canContinue() -> Bool {
        return !input.isEmpty && input.count <= maxChars
    }
    
    func onContinue() {
        print("onContinue")
    }
}
