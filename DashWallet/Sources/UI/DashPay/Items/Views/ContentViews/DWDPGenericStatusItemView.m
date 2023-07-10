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

#import "DWDPGenericStatusItemView.h"

#import "DWUIKit.h"
#import "UIFont+DWDPItem.h"

@implementation DWDPGenericStatusItemView

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
    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.font = [UIFont dw_itemSubtitleFont];
    statusLabel.adjustsFontForContentSizeCategory = YES;
    statusLabel.textColor = [UIColor dw_tertiaryTextColor];
    statusLabel.numberOfLines = 0;
    statusLabel.textAlignment = NSTextAlignmentRight;
    [self.accessoryView addSubview:statusLabel];
    _statusLabel = statusLabel;

    [statusLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 3 forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [statusLabel.topAnchor constraintEqualToAnchor:self.accessoryView.topAnchor],
        [statusLabel.leadingAnchor constraintEqualToAnchor:self.accessoryView.leadingAnchor],
        [self.accessoryView.trailingAnchor constraintEqualToAnchor:statusLabel.trailingAnchor],
        [self.accessoryView.bottomAnchor constraintEqualToAnchor:statusLabel.bottomAnchor],
    ]];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];

    self.statusLabel.backgroundColor = backgroundColor;
}

@end
