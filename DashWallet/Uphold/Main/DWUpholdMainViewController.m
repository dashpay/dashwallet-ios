//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdMainViewController.h"

#import "DWUpholdMainModel.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdMainViewController ()

@property (strong, nonatomic) IBOutlet UILabel *balanceLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *balanceActivityIndicator;
@property (strong, nonatomic) IBOutlet UIButton *transferButton;
@property (strong, nonatomic) IBOutlet UIButton *buyButton;

@property (strong, nonatomic) DWUpholdMainModel *model;

@end

@implementation DWUpholdMainViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdMainStoryboard" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (DWUpholdMainModel *)model {
    if (!_model) {
        _model = [[DWUpholdMainModel alloc] init];
    }
    return _model;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self mvvm_observe:@"self.model.state" with:^(typeof(self) self, NSNumber * value) {
        switch (self.model.state) {
            case DWUpholdMainModelStateLoading: {
                [self.balanceActivityIndicator startAnimating];
                self.balanceLabel.hidden = YES;
                self.transferButton.enabled = NO;
                self.buyButton.enabled = NO;

                break;
            }
            case DWUpholdMainModelStateDone: {
                [self.balanceActivityIndicator stopAnimating];
                self.balanceLabel.hidden = NO;
                self.balanceLabel.text = [self.model.card.available descriptionWithLocale:[NSLocale currentLocale]];
                self.transferButton.enabled = YES;
                self.buyButton.enabled = YES;

                break;
            }
            case DWUpholdMainModelStateFailed: {
                [self.balanceActivityIndicator stopAnimating];
                self.balanceLabel.hidden = NO;
                self.balanceLabel.text = @"Error"; // TODO: localize
                self.transferButton.enabled = NO;
                self.buyButton.enabled = NO;

                break;
            }
        }
    }];

    [self.model fetch];
}

#pragma mark - Actions

- (IBAction)transferButtonAction:(id)sender {
}

- (IBAction)buyButtonAction:(id)sender {
    NSURL *url = [self.model buyDashURL];
    if (!url) {
        return;
    }

    SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:url];
    [self presentViewController:controller animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
