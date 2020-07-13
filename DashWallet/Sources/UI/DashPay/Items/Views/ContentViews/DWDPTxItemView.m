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

#import "DWDPTxItemView.h"

#import "DWUIKit.h"
#import "UIFont+DWDPItem.h"

@implementation DWDPTxItemView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_statusItemView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_statusItemView];
    }
    return self;
}

- (void)setup_statusItemView {
    UILabel *amountLabel = [[UILabel alloc] init];
    amountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    amountLabel.font = [UIFont dw_itemSubtitleFont];
    amountLabel.adjustsFontForContentSizeCategory = YES;
    amountLabel.textColor = [UIColor dw_darkTitleColor];
    amountLabel.numberOfLines = 0;
    amountLabel.textAlignment = NSTextAlignmentRight;
    [self.accessoryView addSubview:amountLabel];
    _amountLabel = amountLabel;

    [amountLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 3 forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [amountLabel.topAnchor constraintEqualToAnchor:self.accessoryView.topAnchor],
        [amountLabel.leadingAnchor constraintEqualToAnchor:self.accessoryView.leadingAnchor],
        [self.accessoryView.trailingAnchor constraintEqualToAnchor:amountLabel.trailingAnchor],
        [self.accessoryView.bottomAnchor constraintEqualToAnchor:amountLabel.bottomAnchor],
    ]];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];

    self.amountLabel.backgroundColor = backgroundColor;
}
@end
