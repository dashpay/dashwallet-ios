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

#import "DWReceiveModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWReceiveContentView ()

@property (nonatomic, strong) DWReceiveModel *model;

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIButton *qrCodeButton;
@property (strong, nonatomic) IBOutlet UIButton *addressButton;
@property (strong, nonatomic) IBOutlet UIButton *specifyAmountButton;
@property (strong, nonatomic) IBOutlet UIButton *shareButton;

@property (nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

@implementation DWReceiveContentView

- (instancetype)initWithModel:(DWReceiveModel *)model {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _model = model;

        self.backgroundColor = [UIColor dw_backgroundColor];

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

        self.addressButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];

        [self.specifyAmountButton setTitle:NSLocalizedString(@"Specify Amount", nil) forState:UIControlStateNormal];
        [self.shareButton setTitle:NSLocalizedString(@"Share", nil) forState:UIControlStateNormal];

        self.feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];

        [self mvvm_observe:DW_KEYPATH(self, model.paymentAddress)
                      with:^(typeof(self) self, NSString *value) {
                          [self.addressButton setTitle:value forState:UIControlStateNormal];

                          BOOL hasValue = !!value;
                          self.addressButton.hidden = !hasValue;
                          self.specifyAmountButton.enabled = hasValue;
                          self.shareButton.enabled = hasValue;
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeImage)
                      with:^(typeof(self) self, UIImage *value) {
                          [self.qrCodeButton setImage:value forState:UIControlStateNormal];
                          self.qrCodeButton.hidden = (value == nil);
                      }];
    }
    return self;
}

- (void)viewDidAppear {
    [self.feedbackGenerator prepare];
}

- (void)setSpecifyAmountButtonHidden:(BOOL)hidden {
    self.specifyAmountButton.hidden = hidden;
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

- (IBAction)shareButtonAction:(UIButton *)sender {
    [self.delegate receiveContentView:self shareButtonAction:sender];
}

@end

NS_ASSUME_NONNULL_END
