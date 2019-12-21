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

#ifndef DWTxDetailDisplayType_h
#define DWTxDetailDisplayType_h

typedef NS_ENUM(NSUInteger, DWTxDetailDisplayType) {
    DWTxDetailDisplayType_Moved,
    DWTxDetailDisplayType_Sent,
    DWTxDetailDisplayType_Received,
    DWTxDetailDisplayType_Paid, // (v) icon, info screen for tx that has been just sent
    DWTxDetailDisplayType_MasternodeRegistration,
};

#endif /* DWTxDetailDisplayType_h */
