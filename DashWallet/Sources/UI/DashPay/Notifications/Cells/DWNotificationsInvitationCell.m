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

#import "DWNotificationsInvitationCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsInvitationCell ()

@property (readonly, nonatomic, strong) NSLayoutConstraint *contentWidthConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsInvitationCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIView *view = [[UIView alloc] init];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        view.backgroundColor = [UIColor dw_lightBlueColor];
        view.layer.cornerRadius = 8;
        view.layer.masksToBounds = YES;
        [self.contentView addSubview:view];


        UIImage *image = [UIImage imageNamed:@"menu_invite"];
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:image];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:iconImageView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.text = NSLocalizedString(@"Invite your friends and family to the Dash Network", nil);
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        [view addSubview:titleLabel];

        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [closeButton setTitle:@"X" forState:UIControlStateNormal];
        closeButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        [closeButton setTitleColor:[UIColor dw_darkTitleColor] forState:UIControlStateNormal];
        [closeButton addTarget:self
                        action:@selector(closeButtonAction)
              forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:closeButton];

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [iconImageView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                       forAxis:UILayoutConstraintAxisHorizontal];
        [iconImageView setContentHuggingPriority:UILayoutPriorityDefaultLow + 10
                                         forAxis:UILayoutConstraintAxisHorizontal];
        [view setContentCompressionResistancePriority:UILayoutPriorityRequired
                                              forAxis:UILayoutConstraintAxisVertical];

        _contentWidthConstraint = [self.contentView.widthAnchor constraintEqualToConstant:300];

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            _contentWidthConstraint,

            [view.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [view.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                               constant:8],
            [guide.trailingAnchor constraintEqualToAnchor:view.trailingAnchor
                                                 constant:8],
            [guide.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],

            [iconImageView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor
                                                        constant:16],
            [iconImageView.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
            [iconImageView.topAnchor constraintGreaterThanOrEqualToAnchor:view.topAnchor],
            [view.bottomAnchor constraintGreaterThanOrEqualToAnchor:iconImageView.bottomAnchor],

            [titleLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor
                                                     constant:12],
            [titleLabel.topAnchor constraintEqualToAnchor:view.topAnchor
                                                 constant:16],
            [view.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                              constant:16],

            [closeButton.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                      constant:12],
            [view.trailingAnchor constraintEqualToAnchor:closeButton.trailingAnchor],
            [closeButton.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
            [closeButton.widthAnchor constraintEqualToConstant:44],
            [closeButton.heightAnchor constraintEqualToConstant:44],
            [closeButton.topAnchor constraintGreaterThanOrEqualToAnchor:view.topAnchor],
            [view.bottomAnchor constraintGreaterThanOrEqualToAnchor:closeButton.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setContentWidth:(CGFloat)contentWidth {
    self.contentWidthConstraint.constant = contentWidth;
}

- (void)closeButtonAction {
    [self.delegate notificationsInvitationCellCloseAction:self];
}

@end
