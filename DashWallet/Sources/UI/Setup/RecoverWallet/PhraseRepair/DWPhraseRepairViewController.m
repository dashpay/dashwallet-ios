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
@property (nullable, nonatomic, copy) NSArray<NSString *> *missingWords;

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

        void (^completion)(NSArray<NSString *> *) = ^(NSArray<NSString *> *_Nonnull missingWords) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf finishWithWords:missingWords];
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

- (void)finishWithWords:(NSArray<NSString *> *)words {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Found potential missing words:\n%@", nil),
                                                 [words componentsJoinedByString:@"\n"]];
    self.controller.progress = 1.0;
    self.controller.title = title;

    self.missingWords = words;

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
    if (self.incorrectWord != nil) {
        [self.delegate phraseRepairViewControllerDidFindReplaceWords:self.missingWords
                                                       incorrectWord:self.incorrectWord];
    }
    else {
        [self.delegate phraseRepairViewControllerDidFindLastWords:self.missingWords];
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel {
}

@end
