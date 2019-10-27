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

#import <GameplayKit/GameplayKit.h>

#import "DWSeedWordModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSeedPhraseModel ()

- (instancetype)initByCopyingSeedPhrase:(DWSeedPhraseModel *)seedPhrase NS_DESIGNATED_INITIALIZER;

@end

@implementation DWSeedPhraseModel

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

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (instancetype)initByShufflingSeedPhrase:(DWSeedPhraseModel *)seedPhrase {
    self = [super init];
    if (self) {
        NSMutableArray<DWSeedWordModel *> *words = [NSMutableArray array];
        for (DWSeedWordModel *wordModel in seedPhrase.words) {
            DWSeedWordModel *newWord = [wordModel copy];
            newWord.selected = NO;
            newWord.visible = NO;
            [words addObject:newWord];
        }

        _words = [words shuffledArray];
    }
    return self;
}

- (instancetype)initByCopyingSeedPhrase:(DWSeedPhraseModel *)seedPhrase {
    self = [super init];
    if (self) {
        NSMutableArray<DWSeedWordModel *> *words = [NSMutableArray array];
        for (DWSeedWordModel *wordModel in seedPhrase.words) {
            DWSeedWordModel *newWord = [wordModel copy];
            newWord.selected = NO;
            newWord.visible = NO;
            [words addObject:newWord];
        }

        _words = [words copy];
    }
    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    typeof(self) copy = [[self.class alloc] initByCopyingSeedPhrase:self];

    return copy;
}

@end

NS_ASSUME_NONNULL_END
