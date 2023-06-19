//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWHistoryHeaderView.h"

#import "DWCreateInvitationButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHistoryHeaderView ()

@property (readonly, nonatomic, strong) DWCreateInvitationButton *createInvitationButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWHistoryHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWCreateInvitationButton *createButton = [[DWCreateInvitationButton alloc] init];
        createButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:createButton];
        _createButton = createButton;

        UILabel *header = [[UILabel alloc] init];
        header.translatesAutoresizingMaskIntoConstraints = NO;
        header.numberOfLines = 0;
        header.adjustsFontForContentSizeCategory = YES;
        header.textColor = [UIColor dw_darkTitleColor];
        header.text = NSLocalizedString(@"Invitations History", nil);
        header.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        [self addSubview:header];

        UIButton *optionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        optionsButton.translatesAutoresizingMaskIntoConstraints = NO;
        [optionsButton setImage:[UIImage imageNamed:@"icon_options"] forState:UIControlStateNormal];
        optionsButton.tintColor = [UIColor dw_dashBlueColor];
        [self addSubview:optionsButton];
        _optionsButton = optionsButton;

        CGFloat const padding = 16;
        UIEdgeInsets const insets = UIEdgeInsetsMake(padding, padding, padding, padding);
        [NSLayoutConstraint dw_activate:@[
            [createButton pinEdges:self
                            insets:insets
                            except:DWAnchorBottom],

            [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                 constant:padding],
            [header.topAnchor constraintEqualToAnchor:createButton.bottomAnchor
                                             constant:20],
            [self.bottomAnchor constraintEqualToAnchor:header.bottomAnchor
                                              constant:20],

            [optionsButton.leadingAnchor constraintEqualToAnchor:header.trailingAnchor
                                                        constant:20],
            [self.trailingAnchor constraintEqualToAnchor:optionsButton.trailingAnchor
                                                constant:5],
            [optionsButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [optionsButton pinSize:CGSizeMake(44, 44)],
        ]];
    }
    return self;
}

@end
