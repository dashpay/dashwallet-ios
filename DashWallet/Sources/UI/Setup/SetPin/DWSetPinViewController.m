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

#import "DWSetPinViewController.h"

#import "DWNumberKeyboard.h"
#import "DWPinView.h"
#import "DWSetPinModel.h"
#import "DevicesCompatibility.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSetPinViewController () <DWPinViewDelegate>

@property (nonatomic, strong) DWSetPinModel *model;

@property (strong, nonatomic) IBOutlet DWPinView *pinView;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet DWNumberKeyboard *keyboardView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWSetPinViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"SetPin" bundle:nil];
    DWSetPinViewController *controller = [storyboard instantiateInitialViewController];
    controller.title = NSLocalizedString(@"Create a New Wallet", nil);
    controller.model = [[DWSetPinModel alloc] init];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.pinView activatePinView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWPinViewDelegate

- (void)pinViewCancelButtonTap:(DWPinView *)pinView {
    [self.delegate setPinViewControllerDidCancel:self];
}

- (void)pinView:(DWPinView *)pinView didFinishWithPin:(NSString *)pin {
    BOOL success = [self.model setPin:pin];
    if (success) {
        [self.delegate setPinViewControllerDidSetPin:self];
    }
    else {
        [self.delegate setPinViewControllerDidCancel:self];
    }
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Create a New Wallet", nil);

    self.descriptionLabel.text = NSLocalizedString(@"This PIN will be required to unlock your app everytime when you use it.", nil);
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];

    [self.pinView configureWithKeyboard:self.keyboardView];
    self.pinView.delegate = self;
}

#pragma mark - Configuration

+ (CGFloat)deviceSpecificBottomPadding {
    if (IS_IPAD) {
        return 24.0;
    }
    else {
        return 4.0;
    }
}

@end

NS_ASSUME_NONNULL_END
