//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWTextField.h"

static CGFloat const HORIZONTAL_PADDING = 30.0;
static CGFloat const VERTICAL_PADDING = 16.0;

@implementation DWTextField

- (CGRect)textRectForBounds:(CGRect)bounds {
    return CGRectInset(bounds, HORIZONTAL_PADDING, VERTICAL_PADDING);
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    return CGRectInset(bounds, HORIZONTAL_PADDING, VERTICAL_PADDING);
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return CGRectInset(bounds, HORIZONTAL_PADDING, VERTICAL_PADDING);
}

@end
