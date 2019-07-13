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

#import "DWSeedPhraseModel.h"

#import "DWSeedWordModel.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWSeedPhraseModel

- (instancetype)initAsNewWallet {
    // TODO: correct language type
    NSString *seed = [DSWallet generateRandomSeedForLanguage:DSBIP39Language_English];
    return [self initWithSeed:seed];
}

- (instancetype)initWithSeed:(NSString *)seed {
    NSParameterAssert(seed);

    self = [super init];
    if (self) {
        NSArray<NSString *> *seedWords = [seed componentsSeparatedByString:@" "];
        NSAssert(seedWords.count > 0, @"Invalid seed phrase");

        NSMutableArray<DWSeedWordModel *> *words = [NSMutableArray array];
        for (NSString *seedWord in seedWords) {
            DWSeedWordModel *word = [[DWSeedWordModel alloc] initWithWord:seedWord];
            [words addObject:word];
        }
        _words = [words copy];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
