//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWDashPaySetupModel.h"

@implementation DWDashPaySetupModel

@synthesize blockchainIdentity;

@synthesize lastRegistrationError;

@synthesize registrationCompleted;

@synthesize registrationStatus;

@synthesize unreadNotificationsCount;

@synthesize username;

@synthesize userProfile;

- (BOOL)canRetry {
    return NO;
}

- (void)completeRegistration {
    // nop
}

- (void)createUsername:(nonnull NSString *)username invitation:(nonnull NSURL *)invitation {
    NSAssert(NO, @"Should not be called");
    // nop
}

- (void)retry {
    NSAssert(NO, @"Should not be called");
    // nop
}

- (void)setHasEnoughBalanceForInvitationNotification:(BOOL)value {
    // nop
}

- (BOOL)shouldPresentRegistrationPaymentConfirmation {
    return YES;
}

- (void)updateUsernameStatus {
    // nop
}

- (void)verifyDeeplink:(nonnull NSURL *)url completion:(nonnull void (^)(BOOL, NSString *_Nullable, NSString *_Nullable))completion {
    NSAssert(NO, @"Should not be called");
    // nop
}

@end
