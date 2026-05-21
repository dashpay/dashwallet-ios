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

#import "DWRecoverContentView.h"

#import "DWRecoverModel.h"
#import "DWSeedUIConstants.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRecoverContentView () <DWRecoverSeedPhraseInputControllerDelegate>

/// Swift bridge that owns the SwiftUI `RecoverSeedPhraseInputView` hosting
/// controller and routes user actions back into Objective-C.
@property (nonatomic, strong) DWRecoverSeedPhraseInputController *inputController;

/// Convenience pointer to the bridged hosting controller's view; kept so we
/// can size DWRecoverContentView against it.
@property (nonatomic, weak) UIView *inputHostView;

@property (nonatomic, assign) BOOL parentViewControllerAttached;

@end

@implementation DWRecoverContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        // Stage 3 bridge: Swift now owns phrase validation + recover/wipe
        // branching. This Objective-C view is a container/forwarder only.
        DWRecoverSeedPhraseInputController *inputController =
            [[DWRecoverSeedPhraseInputController alloc] init];
        self.inputController = inputController;
        inputController.delegate = self;

    }
    return self;
}

- (void)attachToParentViewController:(UIViewController *)parentViewController {
    if (self.parentViewControllerAttached || parentViewController == nil) {
        return;
    }
    UIViewController *child = self.inputController.viewController;
    if (child == nil) {
        return;
    }
    [parentViewController addChildViewController:child];

    UIView *hostView = child.view;
    hostView.translatesAutoresizingMaskIntoConstraints = NO;
    hostView.backgroundColor = self.backgroundColor;
    [self addSubview:hostView];
    self.inputHostView = hostView;

    [NSLayoutConstraint activateConstraints:@[
        [hostView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [hostView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [hostView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [hostView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    [child didMoveToParentViewController:parentViewController];
    self.parentViewControllerAttached = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (!CGSizeEqualToSize(self.bounds.size, [self intrinsicContentSize])) {
        [self invalidateIntrinsicContentSize];
    }
}

- (CGSize)intrinsicContentSize {
    // Mirror the legacy formula so the surrounding scroll view + keyboard
    // handling continue to produce the same content size. We can't ask the
    // SwiftUI host for an exact intrinsic value cheaply, so we approximate
    // using the same constants the SwiftUI Layout enum already uses.
    UIFont *titleFont = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
    const CGFloat titleHeight = titleFont.lineHeight;
    UIFont *wordFont = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    const CGFloat approxLineHeight = wordFont.lineHeight;
    const CGFloat lineSpacing = 10.0;  // matches Layout.lineSpacing
    const CGFloat textInset = 12.0;    // matches Layout.textInset
    const NSInteger numberOfLines = 5; // matches Layout.numberOfLines
    const CGFloat inputMinHeight = approxLineHeight * numberOfLines +
                                   lineSpacing * MAX(numberOfLines - 1, 0) +
                                   textInset * 2.0;

    const CGFloat height = DW_TOP_COMPACT_PADDING +
                           titleHeight +
                           DWTitleSeedPhrasePadding() +
                           inputMinHeight +
                           DW_BOTTOM_PADDING;

    return CGSizeMake(self.visibleSize.width, MAX(height, self.visibleSize.height));
}

- (void)setVisibleSize:(CGSize)visibleSize {
    _visibleSize = visibleSize;

    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (void)setModel:(DWRecoverModel *)model {
    _model = model;
    self.inputController.model = model;
}

- (nullable NSString *)title {
    return self.inputController.title;
}

- (void)setTitle:(nullable NSString *)title {
    self.inputController.title = title ?: @"";
}

- (void)activateTextView {
    [self.inputController activate];
}

- (void)continueAction {
    [self.inputController continueAction];
}

- (void)appendText:(NSString *)text {
    [self.inputController appendText:text];
}

- (void)replaceText:(NSString *)target replacement:(NSString *)replacement {
    [self.inputController replaceText:target with:replacement];
}

#pragma mark - DWRecoverSeedPhraseInputControllerDelegate

- (void)recoverSeedPhraseInputController:(DWRecoverSeedPhraseInputController *)controller
                         phraseDidChange:(NSString *)phrase {
    [self.delegate recoverContentView:self phraseDidChange:phrase];
}

- (void)recoverSeedPhraseInputController:(DWRecoverSeedPhraseInputController *)controller
                       showIncorrectWord:(NSString *)incorrectWord {
    [self.delegate recoverContentView:self showIncorrectWord:incorrectWord];
}

- (void)recoverSeedPhraseInputController:(DWRecoverSeedPhraseInputController *)controller
             offerToReplaceIncorrectWord:(NSString *)incorrectWord
                                inPhrase:(NSString *)phrase {
    [self.delegate recoverContentView:self offerToReplaceIncorrectWord:incorrectWord inPhrase:phrase];
}

- (void)recoverSeedPhraseInputController:(DWRecoverSeedPhraseInputController *)controller
               usedWordsHaveInvalidCount:(NSArray *)words {
    [self.delegate recoverContentView:self usedWordsHaveInvalidCount:words];
}

- (void)recoverSeedPhraseInputControllerBadRecoveryPhrase:(DWRecoverSeedPhraseInputController *)controller {
    [self.delegate recoverContentViewBadRecoveryPhrase:self];
}

- (void)recoverSeedPhraseInputController:(DWRecoverSeedPhraseInputController *)controller
                    didRecoverWalletWith:(NSString *)phrase {
    [self.delegate recoverContentViewDidRecoverWallet:self phrase:phrase];
}

- (void)recoverSeedPhraseInputControllerPerformWipe:(DWRecoverSeedPhraseInputController *)controller {
    [self.delegate recoverContentViewPerformWipe:self];
}

- (void)recoverSeedPhraseInputControllerWipeNotAllowed:(DWRecoverSeedPhraseInputController *)controller {
    [self.delegate recoverContentViewWipeNotAllowed:self];
}

- (void)recoverSeedPhraseInputControllerWipeNotAllowedPhraseMismatch:(DWRecoverSeedPhraseInputController *)controller {
    [self.delegate recoverContentViewWipeNotAllowedPhraseMismatch:self];
}

@end

NS_ASSUME_NONNULL_END
