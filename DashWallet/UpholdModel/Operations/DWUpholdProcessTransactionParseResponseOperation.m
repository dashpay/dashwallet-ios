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

#import "DWUpholdProcessTransactionParseResponseOperation.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdProcessTransactionParseResponseOperation ()

@property (assign, nonatomic) DWUpholdProcessTransactionParseResponseOperationResult result;

@end

@implementation DWUpholdProcessTransactionParseResponseOperation

- (void)execute {
    NSParameterAssert(self.httpOperationResult.parsedResponse);
    
    NSDictionary *response = (NSDictionary *)self.httpOperationResult.parsedResponse;
    if (![response isKindOfClass:NSDictionary.class]) {
        [self cancelWithError:[self.class invalidResponseErrorWithUserInfo:@{NSDebugDescriptionErrorKey : response}]];
        
        return;
    }
    
    DWUpholdProcessTransactionParseResponseOperationResult result = DWUpholdProcessTransactionParseResponseOperationResultSuccess;
    NSDictionary *errors = response[@"errors"];
    if ([errors isKindOfClass:NSDictionary.class] && errors[@"token"] != nil) {
        result = DWUpholdProcessTransactionParseResponseOperationResultOTPError;
    }
    
    self.result = result;
    
    [self finish];
}

@end

NS_ASSUME_NONNULL_END
