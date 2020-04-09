//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWDPRegistrationStatus.h"

@implementation DWDPRegistrationStatus

- (instancetype)initWithState:(DWDPRegistrationState)state failed:(BOOL)failed username:(NSString *)username {
    self = [super init];
    if (self) {
        _state = state;
        _failed = failed;
        _username = [username copy];
    }
    return self;
}

- (NSString *)stateDescription {
    if (self.failed) {
        switch (self.state) {
            case DWDPRegistrationState_ProcessingPayment:
                return NSLocalizedString(@"(1/3) Unable to process payment", nil);
            case DWDPRegistrationState_CreatingID:
                return NSLocalizedString(@"(2/3) Unable to create ID", nil);
            case DWDPRegistrationState_RegistrationUsername:
                return NSLocalizedString(@"(3/3) Can't register username", nil);
            case DWDPRegistrationState_Done:
                NSAssert(NO, @"Invalid state");
                return @"";
        }
    }
    else {
        switch (self.state) {
            case DWDPRegistrationState_ProcessingPayment:
                return NSLocalizedString(@"(1/3) Processing Payment", nil);
            case DWDPRegistrationState_CreatingID:
                return NSLocalizedString(@"(2/3) Creating ID", nil);
            case DWDPRegistrationState_RegistrationUsername:
                return NSLocalizedString(@"(3/3) Registering Username", nil);
            case DWDPRegistrationState_Done:
                return NSLocalizedString(@"Your DashPay Username is ready to use", nil);
        }
    }
}

- (float)progress {
    switch (self.state) {
        case DWDPRegistrationState_ProcessingPayment:
            return 1.0 / 3.0;
        case DWDPRegistrationState_CreatingID:
            return 2.0 / 3.0;
        case DWDPRegistrationState_RegistrationUsername:
            return 0.9;
        case DWDPRegistrationState_Done:
            return 1.0;
    }
}

@end
