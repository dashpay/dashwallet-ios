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

#import "UIView+DWFindConstraints.h"

@implementation UIView (DWFindConstraints)

- (NSLayoutConstraint *)dw_findConstraintWithAttribute:(NSLayoutAttribute)layoutAttribute {
    for (NSLayoutConstraint *constraint in self.superview.constraints) {
        if ([self dw_itemsMatchConstraint:constraint layoutAttribute:layoutAttribute]) {
            return constraint;
        }
    }

    return nil;
}

- (BOOL)dw_itemsMatchConstraint:(NSLayoutConstraint *)constraint layoutAttribute:(NSLayoutAttribute)layoutAttribute {
    const id firstItem = constraint.firstItem;
    const id secondItem = constraint.secondItem;
    if (firstItem && secondItem) {
        const BOOL firstItemMatch = firstItem == self && constraint.firstAttribute == layoutAttribute;
        const BOOL secondItemMatch = secondItem == self && constraint.secondAttribute == layoutAttribute;
        return firstItemMatch || secondItemMatch;
    }
    return NO;
}

@end
