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

#import "DWUserProfileModalQRContentView.h"

#import "DSBlockchainIdentity+DWDisplayTitleSubtitle.h"
#import "DWActionButton.h"
#import "DWEnvironment.h"
#import "DWReceiveModelProtocol.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const ButtonHeight = 39.0;

@interface DWUserProfileModalQRContentView ()

@property (nonatomic, strong) id<DWReceiveModelProtocol> model;

@property (readonly, strong, nonatomic) UIButton *qrCodeButton;
@property (readonly, strong, nonatomic) UILabel *infoLabel;

@property (nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileModalQRContentView

- (instancetype)initWithModel:(id<DWReceiveModelProtocol>)model {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _model = model;

        self.backgroundColor = [UIColor dw_backgroundColor];

        _feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = self.backgroundColor;
        [self addSubview:contentView];

        UIButton *qrCodeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        qrCodeButton.translatesAutoresizingMaskIntoConstraints = NO;
        qrCodeButton.backgroundColor = [UIColor whiteColor];
        [qrCodeButton addTarget:self action:@selector(qrCodeButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [contentView addSubview:qrCodeButton];
        _qrCodeButton = qrCodeButton;

        UILabel *infoLabel = [[UILabel alloc] init];
        infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        infoLabel.numberOfLines = 0;
        infoLabel.textAlignment = NSTextAlignmentCenter;
        [contentView addSubview:infoLabel];
        _infoLabel = infoLabel;

        DWActionButton *shareButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        shareButton.usedOnDarkBackground = NO;
        shareButton.small = YES;
        [shareButton setTitle:NSLocalizedString(@"Share", nil) forState:UIControlStateNormal];
        [shareButton addTarget:self
                        action:@selector(shareButtonAction:)
              forControlEvents:UIControlEventTouchUpInside];

        DWActionButton *closeButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        closeButton.usedOnDarkBackground = NO;
        closeButton.small = YES;
        closeButton.inverted = YES;
        [closeButton setTitle:NSLocalizedString(@"Close", nil) forState:UIControlStateNormal];
        [closeButton addTarget:self
                        action:@selector(closeButtonAction:)
              forControlEvents:UIControlEventTouchUpInside];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ shareButton, closeButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 10.0;
        [contentView addSubview:stackView];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAttributedData)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];

        const CGFloat spacing = 44.0;
        const CGSize qrSize = model.qrCodeSize;
        const CGFloat interitem = 24.0;
        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor],
            [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                      constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                constant:padding],

            [qrCodeButton.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                   constant:spacing],
            [qrCodeButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
            [qrCodeButton.widthAnchor constraintEqualToConstant:qrSize.width],
            [qrCodeButton.heightAnchor constraintEqualToConstant:qrSize.height],

            [infoLabel.topAnchor constraintEqualToAnchor:qrCodeButton.bottomAnchor
                                                constant:interitem],
            [infoLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:infoLabel.trailingAnchor],

            [stackView.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor
                                                constant:interitem],
            [stackView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
            //            [stackView.centerXAnchor ]
            //            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
            //                                                    constant:padding],
            //            [self.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor
            //                                                constant:padding],
            [contentView.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                     constant:spacing],

            [shareButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [closeButton.heightAnchor constraintEqualToConstant:ButtonHeight],
        ]];

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeImage)
                      with:^(typeof(self) self, UIImage *value) {
                          [self.qrCodeButton setImage:value forState:UIControlStateNormal];
                          self.qrCodeButton.hidden = (value == nil);
                      }];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)viewDidAppear {
    [self reloadAttributedData];
    [self.feedbackGenerator prepare];
}

- (void)reloadAttributedData {
    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    self.infoLabel.attributedText = [blockchainIdentity dw_asTitleSubtitle];
}

- (void)qrCodeButtonAction {
    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];

    [self.model copyQRImageToPasteboard];
}

- (void)shareButtonAction:(UIButton *)sender {
    [self.delegate userProfileModalQRContentView:self shareButtonAction:sender];
}

- (void)closeButtonAction:(UIButton *)sender {
    [self.delegate userProfileModalQRContentView:self closeButtonAction:sender];
}

@end
