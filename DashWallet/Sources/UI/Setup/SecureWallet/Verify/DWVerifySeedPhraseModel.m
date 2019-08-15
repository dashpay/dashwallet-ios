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

#import "DWVerifySeedPhraseModel.h"

#import "DWGlobalOptions.h"
#import "DWSeedPhraseModel.h"
#import "DWSeedWordModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWVerifySeedPhraseModel ()

@property (nonatomic, assign) BOOL seedPhraseHasBeenVerified;

@end

@implementation DWVerifySeedPhraseModel

- (instancetype)initWithSeedPhrase:(DWSeedPhraseModel *)seedPhrase {
    self = [super init];
    if (self) {
        // copy seedPhrase to produce new editable instances of DWSeedWordModel
        _seedPhrase = [seedPhrase copy];
        _shuffledSeedPhrase = [[DWSeedPhraseModel alloc] initByShufflingSeedPhrase:seedPhrase];
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (BOOL)allowedToSelectWord:(DWSeedWordModel *)sampleWordModel {
    if (sampleWordModel.isSelected) {
        return NO;
    }

    // Allow if: not visible AND (it's first OR prev is visible)

    DWSeedPhraseModel *const seedPhrase = self.seedPhrase;
    NSArray<DWSeedWordModel *> *const words = seedPhrase.words;
    for (NSUInteger i = 0; i < words.count; i++) {
        DWSeedWordModel *wordModel = words[i];
        if (wordModel.isVisible) {
            continue;
        }

        if ([wordModel isEqual:sampleWordModel]) {
            if (i == 0) {
                return YES;
            }
            else {
                DWSeedWordModel *previousWordModel = words[i - 1];
                return previousWordModel.isVisible;
            }
        }
    }

    return NO;
}

- (void)selectWord:(DWSeedWordModel *)sampleWordModel {
    DWSeedWordModel *wordModel = [self firstNotVisibleWordMatching:sampleWordModel];
    NSAssert(wordModel, @"Matching word model must be found");
    if (!wordModel) {
        return;
    }

    NSAssert(!sampleWordModel.selected, @"Word is already selected");
    sampleWordModel.selected = YES;

    NSAssert(!wordModel.visible, @"Word is already verified");
    wordModel.visible = YES;

    DWSeedPhraseModel *const seedPhrase = self.seedPhrase;
    NSArray<DWSeedWordModel *> *const words = seedPhrase.words;
    if (wordModel == words.lastObject) {
        self.seedPhraseHasBeenVerified = YES;

        [DWGlobalOptions sharedInstance].walletNeedsBackup = NO;
    }
}

- (nullable DWSeedWordModel *)firstNotVisibleWordMatching:(DWSeedWordModel *)sampleWordModel {
    DWSeedPhraseModel *const seedPhrase = self.seedPhrase;
    NSArray<DWSeedWordModel *> *const words = seedPhrase.words;
    for (DWSeedWordModel *wordModel in words) {
        if (wordModel.isVisible == NO && [wordModel isEqual:sampleWordModel]) {
            return wordModel;
        }
    }

    return nil;
}

@end

NS_ASSUME_NONNULL_END
