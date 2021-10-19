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

#import "DWPhraseRepairViewController.h"

#import "DWEnvironment.h"
#import "DWPhraseRepairChildViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPhraseRepairViewController ()

@property (readonly, nonatomic, strong) DWPhraseRepairChildViewController *controller;

@property (atomic, assign) BOOL cancelled;

@property (nullable, nonatomic, copy) NSString *incorrectWord;
@property (nullable, nonatomic, copy) NSArray<NSString *> *missingWordsArray;

@end

NS_ASSUME_NONNULL_END

@implementation DWPhraseRepairViewController

- (instancetype)initWithPhrase:(NSString *)phrase incorrectWord:(nullable NSString *)incorrectWord {
    DWPhraseRepairChildViewController *controller = [[DWPhraseRepairChildViewController alloc] init];
    controller.title = NSLocalizedString(@"Recovering...", nil);

    self = [super initWithContentController:controller];
    if (self) {
        _controller = controller;
        _incorrectWord = [incorrectWord copy];

        __weak typeof(self) weakSelf = self;

        void (^progressBlock)(float, bool *) = ^(float progress, bool *stop) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.controller.progress = progress;

                if (strongSelf.cancelled) {
                    *stop = true;
                    [strongSelf dismissViewControllerAnimated:YES completion:nil];
                }
            });
        };

        void (^completion)(NSDictionary<NSString *, NSNumber *> *) = ^(NSDictionary<NSString *, NSNumber *> *_Nonnull missingWordsDictionary) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            if ([missingWordsDictionary count] == 1 && [[[missingWordsDictionary allValues] firstObject] unsignedIntegerValue] == DSBIP39RecoveryWordConfidence_Max) {
                [strongSelf finishWithFoundWords:[[missingWordsDictionary allKeys] firstObject]];
            }
            else if ([missingWordsDictionary count] > 0) {
                [strongSelf finishWithPotentialWords:[missingWordsDictionary keysSortedByValueUsingComparator:^NSComparisonResult(id _Nonnull obj1, id _Nonnull obj2) {
                                return [(NSNumber *)obj1 compare:obj2];
                            }]];
            }
            else {
                [strongSelf noWordsFound];
            }
        };

        if (incorrectWord != nil) {
            [[DSBIP39Mnemonic sharedInstance] findPotentialWordsOfMnemonicForPassphrase:phrase
                                                                      replacementString:incorrectWord
                                                                         progressUpdate:progressBlock
                                                                             completion:completion];
        }
        else {
            [[DSBIP39Mnemonic sharedInstance] findLastPotentialWordsOfMnemonicForPassphrase:phrase
                                                                             progressUpdate:progressBlock
                                                                                 completion:completion];
        }

        DWAlertAction *action = [DWAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:DWAlertActionStyleCancel
                    handler:^(DWAlertAction *_Nonnull action) {
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) {
                            return;
                        }

                        strongSelf.cancelled = YES;
                        action.enabled = NO;
                    }];
        [self setupActions:@[ action ]];
    }
    return self;
}

- (void)noWordsFound {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSString *title = NSLocalizedString(@"Could not automatically recover missing or incorrect words", nil);
    self.controller.progress = 1.0;
    self.controller.title = title;

    self.missingWordsArray = nil;

    __weak typeof(self) weakSelf = self;
    DWAlertAction *action = [DWAlertAction
        actionWithTitle:NSLocalizedString(@"OK", nil)
                  style:DWAlertActionStyleCancel
                handler:^(DWAlertAction *_Nonnull action) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }

                    [strongSelf done];
                }];
    [self setupActions:@[ action ]];
}

- (void)finishWithPotentialWords:(NSArray<NSString *> *)potentialWords {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Found potential missing words:\n%@", nil),
                                                 [potentialWords componentsJoinedByString:@"\n"]];
    self.controller.progress = 1.0;
    self.controller.title = title;

    self.missingWordsArray = potentialWords;

    __weak typeof(self) weakSelf = self;
    uint32_t i = 0;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *potentialWord in potentialWords) {
        if (i > 4)
            break;
        DWAlertAction *action = [DWAlertAction
            actionWithTitle:potentialWord
                      style:DWAlertActionStyleDefault
                    handler:^(DWAlertAction *_Nonnull action) {
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) {
                            return;
                        }
                        self.missingWordsArray = @[ potentialWord ];

                        [strongSelf done];
                    }];
        [actions addObject:action];
        i++;
    }
    DWAlertAction *cancel = [DWAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:DWAlertActionStyleCancel
                handler:^(DWAlertAction *_Nonnull action) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }
                    self.missingWordsArray = @[];

                    [strongSelf done];
                }];
    [actions addObject:cancel];
    [self setupActions:actions];
}

- (void)finishWithFoundWords:(NSString *)words {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSString *title;

    if ([words containsString:@" "]) {
        title = [NSString stringWithFormat:NSLocalizedString(@"Found missing words:\n%@", nil),
                                           words];
    }
    else {
        title = [NSString stringWithFormat:NSLocalizedString(@"Found missing word:\n%@", nil), words];
    }
    self.controller.progress = 1.0;
    self.controller.title = title;

    self.missingWordsArray = @[ words ];

    __weak typeof(self) weakSelf = self;
    DWAlertAction *action = [DWAlertAction
        actionWithTitle:NSLocalizedString(@"OK", nil)
                  style:DWAlertActionStyleCancel
                handler:^(DWAlertAction *_Nonnull action) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }

                    [strongSelf done];
                }];
    [self setupActions:@[ action ]];
}

- (void)done {
    if (self.missingWordsArray.count) {
        if (self.incorrectWord != nil) {
            [self.delegate phraseRepairViewControllerDidFindReplaceWords:self.missingWordsArray
                                                           incorrectWord:self.incorrectWord];
        }
        else {
            [self.delegate phraseRepairViewControllerDidFindLastWords:self.missingWordsArray];
        }
    }

    [self dismissViewControllerAnimated:YES
                             completion:nil];
}

- (void)cancel {
}

@end
