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

#ifndef DWAlertInternalConstants_h
#define DWAlertInternalConstants_h

// Default iOS UIAlertController's constants

static CGFloat const DWAlertViewWidth = 270.0;
static CGFloat const DWAlertViewCornerRadius = 13.0;
static CGFloat const DWAlertViewActionButtonHeight = 44.0;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"
static CGFloat DWAlertViewSeparatorSize() {
    return 1.0 / [UIScreen mainScreen].scale;
}
#pragma clang diagnostic pop

#endif /* DWAlertInternalConstants_h */
