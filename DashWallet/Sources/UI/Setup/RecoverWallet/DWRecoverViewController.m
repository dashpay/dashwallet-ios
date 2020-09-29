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

#import "DWRecoverViewController.h"

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWPhraseRepairViewController.h"
#import "DWRecoverContentView.h"
#import "DWRecoverModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRecoverViewController () <DWRecoverContentViewDelegate, DWPhraseRepairViewControllerDelegate>

@property (nonatomic, strong) DWRecoverModel *model;
@property (nullable, nonatomic, strong) DWRecoverContentView *contentView;

@end

@implementation DWRecoverViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.contentView.visibleSize = self.scrollView.bounds.size;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self ka_startObservingKeyboardNotifications];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.contentView activateTextView];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    [self.contentView continueAction];
}

#pragma mark - DWRecoverContentViewDelegate

- (void)recoverContentView:(DWRecoverContentView *)view showIncorrectWord:(NSString *)incorrectWord {
    NSString *message = [NSString stringWithFormat:
                                      NSLocalizedString(@"\"%@\" is not a recovery phrase word", nil),
                                      incorrectWord];
    [self showAlertWithTitle:nil message:message];
}

- (void)recoverContentView:(DWRecoverContentView *)view offerToReplaceIncorrectWord:(NSString *)incorrectWord inPhrase:(NSString *)phrase {
    NSString *message = [NSString stringWithFormat:
                                      NSLocalizedString(@"\"%@\" is not a recovery phrase word. Would you like to try to recover the correct word that should be in its place?", nil),
                                      incorrectWord];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *_Nonnull action) {
                                                             [self.contentView activateTextView];
                                                         }];
    UIAlertAction *recoverAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Recover", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              DWPhraseRepairViewController *controller =
                                                                  [[DWPhraseRepairViewController alloc] initWithPhrase:phrase
                                                                                                         incorrectWord:incorrectWord];
                                                              controller.delegate = self;
                                                              [self presentViewController:controller animated:YES completion:nil];
                                                          }];
    [alert addAction:cancelAction];
    [alert addAction:recoverAction];
    [self presentViewController:alert animated:YES completion:nil];
    [self showAlertWithTitle:nil message:message];
}

- (void)recoverContentView:(DWRecoverContentView *)view usedWordsHaveInvalidCount:(NSArray *)words {
    if (words.count == 10 || words.count == 11) {
        NSString *message;
        if (words.count == 10) {
            message = [NSString stringWithFormat:NSLocalizedString(@"It would seem like you are attempting to restore your wallet a using a 12 word recovery phrase, however you have only entered 10 words, would you like to automatically recover missing words? This might take around an hour. We recommend plugging in your device.", nil), words.count];
        }
        else {
            message = [NSString stringWithFormat:NSLocalizedString(@"It would seem like you are attempting to restore your wallet a using a 12 word recovery phrase, however you have only entered 11 words, would you like to automatically recover the missing word?", nil), words.count];
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction *_Nonnull action) {
                                                                 [self.contentView activateTextView];
                                                             }];
        UIAlertAction *recoverAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Recover", nil)
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction *_Nonnull action) {
                                                                  DWPhraseRepairViewController *controller =
                                                                      [[DWPhraseRepairViewController alloc] initWithPhrase:[words componentsJoinedByString:@" "]
                                                                                                             incorrectWord:nil];
                                                                  controller.delegate = self;
                                                                  [self presentViewController:controller animated:YES completion:nil];
                                                              }];
        [alert addAction:cancelAction];
        [alert addAction:recoverAction];
        [self presentViewController:alert animated:YES completion:nil];
        [self showAlertWithTitle:nil message:message];
    }
    else {
        NSString *message = NSLocalizedString(@"Recovery phrase must have 12, 15, 18, 21 or 24 words", nil);
        [self showAlertWithTitle:nil message:message];
    }
}

- (void)recoverContentViewBadRecoveryPhrase:(DWRecoverContentView *)view {
    NSString *message = NSLocalizedString(@"Bad recovery phrase", nil);
    [self showAlertWithTitle:nil message:message];
}

- (void)recoverContentViewDidRecoverWallet:(DWRecoverContentView *)view phrase:(NSString *)phrase {
    DWRecoverWalletCommand *recoverCommand = [[DWRecoverWalletCommand alloc] initWithPhrase:phrase];
    [self.delegate recoverViewControllerDidRecoverWallet:self recoverCommand:recoverCommand];
}

- (void)recoverContentViewPerformWipe:(DWRecoverContentView *)view {
    UIAlertControllerStyle style = IS_IPAD ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:style];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *action) {
                                                             [self.contentView activateTextView];
                                                         }];
    [alert addAction:cancelAction];
    UIAlertAction *wipeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Wipe", nil)
                                                         style:UIAlertActionStyleDestructive
                                                       handler:^(UIAlertAction *action) {
                                                           [self.model wipeWallet];
                                                           [self.delegate recoverViewControllerDidWipe:self];
                                                       }];
    [alert addAction:wipeAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)recoverContentViewWipeNotAllowed:(DWRecoverContentView *)view {
    NSString *title = NSLocalizedString(@"This wallet is not empty or sync has not finished, you may not wipe it without the recovery phrase", nil);
    NSString *message = [NSString stringWithFormat:
                                      NSLocalizedString(@"If you still would like to wipe it please input: \"%@\"", nil),
                                      self.model.wipeAcceptPhrase];
    [self showAlertWithTitle:title message:message];
}

- (void)recoverContentViewWipeNotAllowedPhraseMismatch:(DWRecoverContentView *)view {
    NSString *message = NSLocalizedString(@"Recovery phrase doesn't match", nil);
    [self showAlertWithTitle:nil message:message];
}

#pragma mark - DWPhraseRepairViewControllerDelegate

- (void)phraseRepairViewControllerDidFindLastWords:(NSArray<NSString *> *)lastWords {
    if (lastWords.count > 0) {
        [self.contentView appendText:lastWords.firstObject];
    }
}

- (void)phraseRepairViewControllerDidFindReplaceWords:(NSArray<NSString *> *)words incorrectWord:(NSString *)incorrectWord {
    if (words.count > 0) {
        [self.contentView replaceText:incorrectWord replacement:words.firstObject];
    }
}

#pragma mark - Private

- (void)setupView {
    switch (self.action) {
        case DWRecoverAction_Recover:
            self.title = NSLocalizedString(@"Recover Wallet", nil);
            break;
        case DWRecoverAction_Wipe:
            self.title = NSLocalizedString(@"Wipe Wallet", nil);
            break;
    }

    self.model = [[DWRecoverModel alloc] initWithAction:self.action];

    self.actionButton.enabled = YES;

    DWRecoverContentView *contentView = [[DWRecoverContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.model = self.model;
    contentView.delegate = self;
    contentView.title = NSLocalizedString(@"Enter Recovery Phrase", nil);
    [self.scrollView addSubview:contentView];
    self.contentView = contentView;

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];
}

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    NSLayoutConstraint *bottomConstraint = [self contentBottomConstraint];
    NSParameterAssert(bottomConstraint);
    const CGFloat padding = [self.class deviceSpecificBottomPadding];
    if (height > 0.0) {
        bottomConstraint.constant = height + padding - self.view.safeAreaInsets.bottom;
    }
    else {
        bottomConstraint.constant = padding;
    }
    [self.view layoutIfNeeded];
}

- (void)showAlertWithTitle:(nullable NSString *)title message:(nullable NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleCancel
                                                     handler:^(UIAlertAction *_Nonnull action) {
                                                         [self.contentView activateTextView];
                                                     }];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
