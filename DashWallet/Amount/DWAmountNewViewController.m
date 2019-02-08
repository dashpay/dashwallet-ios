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

#import "DWAmountNewViewController.h"

#import "DWAmountKeyboard.h"
#import "DWAmountKeyboardInputViewAudioFeedback.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat HorizontalPadding() {
    CGFloat screenWidth = CGRectGetWidth([UIScreen mainScreen].bounds);
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return (screenWidth - 400) / 2.0;
    }
    else {
        if (screenWidth > 320.0) {
            return 30.0;
        }
        else {
            return 10.0;
        }
    }
}

@interface DWAmountNewViewController ()

@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet DWAmountKeyboard *amountKeyboard;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *bottomContainerLeadingConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *bottomContainerTrailingConstraint;

@end

@implementation DWAmountNewViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AmountStoryboard" bundle:nil];
    DWAmountNewViewController *controller = [storyboard instantiateInitialViewController];
    return controller;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(cancelButtonAction:)];
    cancelButton.tintColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = cancelButton;

    self.bottomContainerLeadingConstraint.constant = HorizontalPadding();
    self.bottomContainerTrailingConstraint.constant = -HorizontalPadding();

    CGRect inputViewRect = CGRectMake(0.0, 0.0, CGRectGetWidth([UIScreen mainScreen].bounds), 1.0);
    self.textField.inputView = [[DWAmountKeyboardInputViewAudioFeedback alloc] initWithFrame:inputViewRect];
    self.amountKeyboard.textInput = self.textField;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.textField becomeFirstResponder];
}

#pragma mark - Actions

- (void)cancelButtonAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
