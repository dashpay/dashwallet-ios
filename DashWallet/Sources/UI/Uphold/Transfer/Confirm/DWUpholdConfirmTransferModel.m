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

#import "DWUpholdConfirmTransferModel.h"

#import "DWUpholdCardObject.h"
#import "DWUpholdClient.h"
#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdConfirmTransferModel ()

@property (strong, nonatomic) DWUpholdCardObject *card;
@property (assign, nonatomic) DWUpholdConfirmTransferModelState state;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpholdConfirmTransferModel

- (instancetype)initWithCard:(DWUpholdCardObject *)card
                 transaction:(DWUpholdTransactionObject *)transaction {
    self = [super init];
    if (self) {
        _card = card;
        _transaction = transaction;
    }
    return self;
}

- (void)confirmWithOTPToken:(nullable NSString *)otpToken {
    NSParameterAssert(self.stateNotifier);

    self.state = DWUpholdConfirmTransferModelState_Loading;

    DWUpholdClient *client = [DWUpholdClient sharedInstance];
    __weak typeof(self) weakSelf = self;
    [client commitTransaction:self.transaction
                         card:self.card
                     otpToken:otpToken
                   completion:^(BOOL success, BOOL otpRequired) {
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf) {
                           return;
                       }

                       if (otpRequired) {
                           strongSelf.state = DWUpholdConfirmTransferModelState_OTP;
                       }
                       else {
                           strongSelf.state = success ? DWUpholdConfirmTransferModelState_Success : DWUpholdConfirmTransferModelState_Fail;
                       }
                   }];
}

- (void)cancel {
    [[DWUpholdClient sharedInstance] cancelTransaction:self.transaction card:self.card];
}

- (void)resetState {
    self.state = DWUpholdConfirmTransferModelState_None;
}

#pragma mark - Private

- (void)setState:(DWUpholdConfirmTransferModelState)state {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (_state == state) {
        return;
    }

    _state = state;

    [self.stateNotifier upholdConfirmTransferModel:self didUpdateState:state];
}

@end
