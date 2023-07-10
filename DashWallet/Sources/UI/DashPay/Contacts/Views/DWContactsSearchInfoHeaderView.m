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

#import "DWContactsSearchInfoHeaderView.h"

#import "DWUIKit.h"

@implementation DWContactsSearchInfoHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.backgroundColor = self.backgroundColor;
        label.textColor = [UIColor dw_darkTitleColor];
        label.numberOfLines = 0;
        [self addSubview:label];
        _titleLabel = label;

        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

        const CGFloat spacing = 10.0;
        const CGFloat margin = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:self.topAnchor
                                            constant:spacing],
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:margin],
            [self.trailingAnchor constraintEqualToAnchor:label.trailingAnchor
                                                constant:margin],
            [self.bottomAnchor constraintEqualToAnchor:label.bottomAnchor
                                              constant:spacing],
        ]];
    }
    return self;
}

@end
