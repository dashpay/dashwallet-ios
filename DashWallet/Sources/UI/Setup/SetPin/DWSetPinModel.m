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

#import "DWSetPinModel.h"

#import <DashSync/DSAuthenticationManager+Private.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWSetPinModel

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)shouldSetPin {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    NSError *error = nil;
    BOOL hasPin = [authenticationManager hasPin:&error];
    if (error) {
        return NO;
    }
    return !hasPin;
}

- (BOOL)setPin:(NSString *)pin {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    return [authenticationManager setupNewPin:pin];
}

@end

NS_ASSUME_NONNULL_END
