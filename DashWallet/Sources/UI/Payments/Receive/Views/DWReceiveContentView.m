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

#import "DWReceiveContentView.h"

#import "DWReceiveModelProtocol.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat ActionButtonsTopPadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 0.0;
    }
    else {
        return 12.0;
    }
}

@interface DWReceiveContentView ()

@property (nonatomic, strong) id<DWReceiveModelProtocol> model;

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIButton *qrCodeButton;
@property (weak, nonatomic) IBOutlet UILabel *usernameLabel;
@property (strong, nonatomic) IBOutlet UIButton *addressButton;
@property (strong, nonatomic) IBOutlet UIButton *specifyAmountButton;
@property (weak, nonatomic) IBOutlet UIStackView *actionButtonsStackView;
@property (strong, nonatomic) IBOutlet UIButton *secondButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *actionButtonsTopPadding;

@property (nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

@implementation DWReceiveContentView

- (instancetype)initWithModel:(id<DWReceiveModelProtocol>)model {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _model = model;

        [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
        [self addSubview:self.contentView];
        self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        const CGSize qrSize = model.qrCodeSize;
        [NSLayoutConstraint activateConstraints:@[
            [self.qrCodeButton.widthAnchor constraintEqualToConstant:qrSize.width],
            [self.qrCodeButton.heightAnchor constraintEqualToConstant:qrSize.height],
        ]];

        self.usernameLabel.hidden = YES;
        self.addressButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];

        [self.specifyAmountButton setTitle:NSLocalizedString(@"Specify Amount", nil) forState:UIControlStateNormal];

        self.actionButtonsTopPadding.constant = ActionButtonsTopPadding();

        self.feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];

        [self mvvm_observe:DW_KEYPATH(self, model.paymentAddress)
                      with:^(typeof(self) self, NSString *value) {
                          [self.addressButton setTitle:value forState:UIControlStateNormal];

                          BOOL hasValue = !!value;
                          self.addressButton.hidden = !hasValue;
                          self.specifyAmountButton.enabled = hasValue;

                          if (self.viewType == DWReceiveViewType_Default) {
                              self.secondButton.enabled = hasValue;
                          }
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeImage)
                      with:^(typeof(self) self, UIImage *value) {
                          [self.qrCodeButton setImage:value forState:UIControlStateNormal];
                          self.qrCodeButton.hidden = (value == nil);
                      }];
    }
    return self;
}

- (void)setViewType:(DWReceiveViewType)viewType {
    _viewType = viewType;

    NSString *title = nil;
    UIColor *backgroundColor = [UIColor clearColor];
    switch (viewType) {
        case DWReceiveViewType_Default: {
            title = NSLocalizedString(@"Share", nil);

            break;
        }
        case DWReceiveViewType_QuickReceive: {
            title = NSLocalizedString(@"Exit", nil);

            break;
        }
    }
    [self.secondButton setTitle:title
                       forState:UIControlStateNormal];
    self.backgroundColor = backgroundColor;
    self.contentView.backgroundColor = backgroundColor;
}

- (void)viewDidAppear {
    [self.feedbackGenerator prepare];
}

- (void)setSpecifyAmountButtonHidden:(BOOL)hidden {
    self.specifyAmountButton.hidden = hidden;

    if (hidden) {
        self.actionButtonsStackView.axis = UILayoutConstraintAxisVertical;
        self.actionButtonsStackView.alignment = UIStackViewAlignmentCenter;
        [self.secondButton.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor multiplier:0.5].active = YES;
    }
    else {
        NSAssert(NO, @"unused");
    }
}

- (void)setUsernameAttributedText:(NSAttributedString *)string {
    self.usernameLabel.attributedText = string;
    self.usernameLabel.hidden = NO;
}

#pragma mark - Actions

- (IBAction)qrCodeButtonAction:(id)sender {
    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];

    [self.model copyQRImageToPasteboard];
}

- (IBAction)addressButtonAction:(id)sender {
    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];

    [self.model copyAddressToPasteboard];
}

- (IBAction)specifyAmountButtonAction:(UIButton *)sender {
    [self.delegate receiveContentView:self specifyAmountButtonAction:sender];
}

- (IBAction)secondButtonAction:(UIButton *)sender {
    [self.delegate receiveContentView:self secondButtonAction:sender];
}

@end

NS_ASSUME_NONNULL_END
