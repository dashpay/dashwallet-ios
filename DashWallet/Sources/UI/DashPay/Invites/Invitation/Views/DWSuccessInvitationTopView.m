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

#import "DWSuccessInvitationTopView.h"

#import "DWActionButton.h"
#import "DWSuccessInvitationView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSuccessInvitationTopView ()

@property (readonly, nonatomic, strong) DWSuccessInvitationView *iconView;

@end

NS_ASSUME_NONNULL_END

@implementation DWSuccessInvitationTopView

@synthesize previewButton = _previewButton;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        DWSuccessInvitationView *iconView = [[DWSuccessInvitationView alloc] initWithFrame:CGRectZero];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.transform = CGAffineTransformMakeScale(0.68, 0.68);
        [self addSubview:iconView];
        _iconView = iconView;

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = [UIColor dw_darkTitleColor];
        title.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        title.adjustsFontForContentSizeCategory = YES;
        title.text = NSLocalizedString(@"Invitation Created Successfully", nil);
        title.textAlignment = NSTextAlignmentCenter;
        title.numberOfLines = 0;
        [self addSubview:title];

        DWActionButton *previewButton = [[DWActionButton alloc] init];
        previewButton.translatesAutoresizingMaskIntoConstraints = NO;
        previewButton.inverted = YES;
        [previewButton setTitle:NSLocalizedString(@"Preview Invitation", nil) forState:UIControlStateNormal];
        [self addSubview:previewButton];
        _previewButton = previewButton;

        [title setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [iconView.topAnchor constraintEqualToAnchor:self.topAnchor
                                               constant:32.0],
            [iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [title.topAnchor constraintEqualToAnchor:iconView.bottomAnchor
                                            constant:26.0],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:16.0],
            [self.trailingAnchor constraintEqualToAnchor:title.trailingAnchor
                                                constant:16.0],

            [previewButton.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                                    constant:4.0],
            [previewButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                        constant:16.0],
            [self.trailingAnchor constraintEqualToAnchor:previewButton.trailingAnchor
                                                constant:16.0],
            [self.bottomAnchor constraintEqualToAnchor:previewButton.bottomAnchor
                                              constant:4.0],
            [previewButton.heightAnchor constraintEqualToConstant:44.0],
        ]];
    }
    return self;
}

- (void)viewWillAppear {
    [self.iconView prepareForAnimation];
}

- (void)viewDidAppear {
    [self.iconView showAnimated];
}

- (void)setBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self.iconView.blockchainIdentity = blockchainIdentity;
}

@end
