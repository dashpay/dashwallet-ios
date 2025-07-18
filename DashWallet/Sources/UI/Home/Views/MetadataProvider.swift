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

import UIKit
import Combine

struct TxRowMetadata: Equatable {
    var title: String?
    var details: String?
    var iconId: Data?
    var icon: UIImage?
    var secondaryIcon: IconName?
    
    static func == (lhs: TxRowMetadata, rhs: TxRowMetadata) -> Bool {
        return lhs.title == rhs.title &&
               lhs.details == rhs.details &&
               lhs.iconId == rhs.iconId &&
               lhs.secondaryIcon == rhs.secondaryIcon
    }
}

protocol MetadataProvider {
    var availableMetadata: [Data: TxRowMetadata] { get }
    var metadataUpdated: PassthroughSubject<Data, Never> { get }
}
