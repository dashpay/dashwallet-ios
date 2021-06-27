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

#import "DWSendAmountViewController.h"

#import "DWSendAmountModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSendAmountViewController ()

@property (readonly, strong, nonatomic) DWSendAmountModel *sendAmountModel;

@end

@implementation DWSendAmountViewController

- (instancetype)initWithDestination:(NSString *)sendingDestination
                     paymentDetails:(nullable DSPaymentProtocolDetails *)paymentDetails
                        contactItem:(nullable id<DWDPBasicUserItem>)contactItem {
    DWSendAmountModel *model = [[DWSendAmountModel alloc] initWithSendingDestination:sendingDestination
                                                                      paymentDetails:paymentDetails
                                                                         contactItem:contactItem];
    self = [super initWithModel:model];
    return self;
}

- (DWSendAmountModel *)sendAmountModel {
    return (DWSendAmountModel *)self.model;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Send", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Send", nil);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.demoMode) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.model updateAmountWithReplacementString:@"1" range:NSMakeRange(0, 1)];
            id dummySender = nil;
            [self actionButtonAction:dummySender];
        });
    }
}

- (void)insufficientFundsErrorWasShown {
    self.sendAmountModel.insufficientFundsErrorWasShown = YES;
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    BOOL inputValid = [self validateInputAmount];
    if (!inputValid) {
        return;
    }

    if (!self.sendAmountModel.isSendAllowed) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Please wait for the sync to complete", nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];

        return;
    }

    DWSendAmountModel *sendModel = (DWSendAmountModel *)self.model;
    NSAssert([sendModel isKindOfClass:DWSendAmountModel.class], @"Inconsistent state");

    [self.delegate sendAmountViewController:self
                             didInputAmount:sendModel.amount.plainAmount];
}

@end

NS_ASSUME_NONNULL_END
