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

#import "DWUpholdGetCardParseResponseOperation.h"

#import "DWUpholdCardObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdGetCardParseResponseOperation ()

@property (nullable, strong, nonatomic) DWUpholdCardObject *card;

@end

@implementation DWUpholdGetCardParseResponseOperation

- (void)execute {
    NSParameterAssert(self.httpOperationResult.parsedResponse);

    NSArray *response = (NSArray *)self.httpOperationResult.parsedResponse;
    if (![response isKindOfClass:NSArray.class]) {
        [self cancelWithError:[self.class invalidResponseErrorWithUserInfo:@{NSDebugDescriptionErrorKey : response}]];

        return;
    }

    NSDictionary *dashCardDictionary = nil;
    for (NSDictionary *dictionary in response) {
        if (![dictionary isKindOfClass:NSDictionary.class]) {
            [self cancelWithError:[self.class invalidResponseErrorWithUserInfo:@{NSDebugDescriptionErrorKey : response}]];

            return;
        }

        NSString *currency = dictionary[@"currency"];
        if (![currency isKindOfClass:NSString.class]) {
            [self cancelWithError:[self.class invalidResponseErrorWithUserInfo:@{NSDebugDescriptionErrorKey : response}]];

            return;
        }

        if ([currency caseInsensitiveCompare:@"DASH"] == NSOrderedSame) {
            dashCardDictionary = dictionary;
            break;
        }
    }

    if (dashCardDictionary) {
        self.card = [[DWUpholdCardObject alloc] initWithDictionary:dashCardDictionary];
    }

    [self finish];
}

@end

NS_ASSUME_NONNULL_END
