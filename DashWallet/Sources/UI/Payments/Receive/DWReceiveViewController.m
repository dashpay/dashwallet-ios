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

#import "DWReceiveViewController.h"

#import "DWReceiveModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWReceiveViewController ()

@property (strong, nonatomic) IBOutlet UIButton *qrCodeButton;
@property (strong, nonatomic) IBOutlet UIButton *addressButton;
@property (strong, nonatomic) IBOutlet UIButton *specifyAmountButton;
@property (strong, nonatomic) IBOutlet UIButton *shareButton;

@property (nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@property (nonatomic, strong) DWReceiveModel *model;

@end

@implementation DWReceiveViewController

+ (instancetype)controllerWithModel:(DWReceiveModel *)receiveModel {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Receive" bundle:nil];
    DWReceiveViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = receiveModel;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSAssert(self.model, @"Use controllerWithModel: method to init the class");

    [self setupView];
    [self setupObserving];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.feedbackGenerator prepare];
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

- (IBAction)specifyAmountButtonAction:(id)sender {
    // TODO: impl
}

- (IBAction)shareButtonAction:(UIButton *)sender {
    NSMutableArray *activityItems = [NSMutableArray array];

    if (self.model.paymentAddress) {
        [activityItems addObject:self.model.paymentAddress];
    }

    if (self.model.qrCodeImage) {
        [activityItems addObject:self.model.qrCodeImage];
    }

    NSAssert(activityItems.count > 0, @"Invalid state");
    if (activityItems.count == 0) {
        return;
    }

    UIActivityViewController *activityViewController =
        [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                          applicationActivities:nil];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityViewController.popoverPresentationController.sourceView = sender;
        activityViewController.popoverPresentationController.sourceRect = sender.bounds;
    }
    [self presentViewController:activityViewController animated:YES completion:nil];
}

#pragma mark - Private

- (void)setupView {
    const CGSize qrSize = self.model.qrCodeSize;
    [NSLayoutConstraint activateConstraints:@[
        [self.qrCodeButton.widthAnchor constraintEqualToConstant:qrSize.width],
        [self.qrCodeButton.heightAnchor constraintEqualToConstant:qrSize.height],
    ]];

    self.addressButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];

    [self.specifyAmountButton setTitle:NSLocalizedString(@"Specify Amount", nil) forState:UIControlStateNormal];
    [self.shareButton setTitle:NSLocalizedString(@"Share", nil) forState:UIControlStateNormal];

    self.feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
}

- (void)setupObserving {
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

@end

NS_ASSUME_NONNULL_END
