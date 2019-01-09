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

#import "DWUpholdSuccessTransferViewController.h"

#import "DWUpholdSuccessTransferModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdSuccessTransferViewController ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UILabel *transactionLabel;
@property (strong, nonatomic) IBOutlet UIButton *okButton;
@property (strong, nonatomic) IBOutlet UIButton *seeOnUpholdButton;

@property (strong, nonatomic) DWUpholdSuccessTransferModel *model;

@end

@implementation DWUpholdSuccessTransferViewController

+ (instancetype)controllerWithTransaction:(DWUpholdTransactionObject *)transaction {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdSuccessTransferStoryboard" bundle:nil];
    DWUpholdSuccessTransferViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdSuccessTransferModel alloc] initWithTransaction:transaction];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Success", nil);
    self.descriptionLabel.text = NSLocalizedString(@"Your transaction was sent and the amount should appear in your wallet in a few minutes.", nil);
    self.transactionLabel.text = [self.model transactionText];
    [self.okButton setTitle:NSLocalizedString(@"OK", nil) forState:UIControlStateNormal];
    [self.seeOnUpholdButton setTitle:NSLocalizedString(@"See on Uphold", nil) forState:UIControlStateNormal];
}

- (IBAction)seeOnUpholdButtonAction:(id)sender {
    [self.delegate upholdSuccessTransferViewControllerDidFinish:self
                                             openTransactionURL:[self.model transactionURL]];
}

- (IBAction)okButtonAction:(id)sender {
    [self.delegate upholdSuccessTransferViewControllerDidFinish:self];
}

@end

NS_ASSUME_NONNULL_END
