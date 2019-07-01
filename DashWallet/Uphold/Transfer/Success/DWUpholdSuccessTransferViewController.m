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

@property (strong, nonatomic) DWUpholdSuccessTransferModel *model;

@end

@implementation DWUpholdSuccessTransferViewController

@synthesize providedActions = _providedActions;

+ (instancetype)controllerWithTransaction:(DWUpholdTransactionObject *)transaction {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdSuccessTransferStoryboard" bundle:nil];
    DWUpholdSuccessTransferViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdSuccessTransferModel alloc] initWithTransaction:transaction];

    return controller;
}

- (NSArray<DWAlertAction *> *)providedActions {
    if (!_providedActions) {
        __weak typeof(self) weakSelf = self;
        DWAlertAction *cancelAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:DWAlertActionStyleCancel handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf okButtonAction];
        }];
        DWAlertAction *seeOnUpholdAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"See on Uphold", nil) style:DWAlertActionStyleDefault handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf seeOnUpholdButtonAction];
        }];
        _providedActions = @[ cancelAction, seeOnUpholdAction ];
    }
    return _providedActions;
}

- (DWAlertAction *)preferredAction {
    return self.providedActions.lastObject;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Success", nil);
    self.descriptionLabel.text = NSLocalizedString(@"Your transaction was sent and the amount should appear in your wallet in a few minutes.", nil);
    self.transactionLabel.text = [self.model transactionText];
}

- (void)okButtonAction {
    [self.delegate upholdSuccessTransferViewControllerDidFinish:self];
}

- (void)seeOnUpholdButtonAction {
    [self.delegate upholdSuccessTransferViewControllerDidFinish:self
                                             openTransactionURL:[self.model transactionURL]];
}

@end

NS_ASSUME_NONNULL_END
