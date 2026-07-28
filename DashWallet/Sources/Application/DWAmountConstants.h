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

#ifndef DWAmountConstants_h
#define DWAmountConstants_h

/// Number of duffs in one DASH. Kept as a compile-time constant for Objective-C
/// global initializers and imported into Swift through the bridging header.
#define DW_DUFFS_PER_DASH 100000000LL

/// Maximum DASH supply expressed in duffs.
#define DW_MAX_MONEY (21000000LL * DW_DUFFS_PER_DASH)

#endif /* DWAmountConstants_h */
