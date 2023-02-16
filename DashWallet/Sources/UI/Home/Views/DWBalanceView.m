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

#import "DWBalanceView.h"

#import "DWBalanceDisplayOptionsProtocol.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const BalanceButtonMinHeight(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 80.0;
    }
    else {
        return 120.0;
    }
}

static NSTimeInterval const ANIMATION_DURATION = 0.3;

@interface DWBalanceView ()

@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIControl *balanceButton;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UIView *hidingView;
@property (strong, nonatomic) IBOutlet UIImageView *eyeSlashImageView;
@property (strong, nonatomic) IBOutlet UILabel *tapToUnhideLabel;
@property (strong, nonatomic) IBOutlet UIView *amountsView;
@property (strong, nonatomic) IBOutlet UILabel *dashBalanceLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatBalanceLabel;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *balanceViewHeightContraint;

@end

@implementation DWBalanceView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
    [self addSubview:self.contentView];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
    ]];

    self.backgroundColor = [UIColor dw_backgroundColor];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    self.titleLabel.textColor = [UIColor colorWithRed:166.0 / 255.0 green:215.0 / 255.0 blue:245.0 / 255.0 alpha:1.0];

    self.eyeSlashImageView.tintColor = [UIColor dw_darkBlueColor];

    self.tapToUnhideLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
    self.tapToUnhideLabel.textColor = [UIColor dw_lightTitleColor];
    self.tapToUnhideLabel.alpha = 0.5;

    self.dashBalanceLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle1];
    self.fiatBalanceLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];

    self.balanceViewHeightContraint.constant = BalanceButtonMinHeight();

    UILongPressGestureRecognizer *recognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(balanceLongPressAction:)];
    [self.balanceButton addGestureRecognizer:recognizer];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];

    // KVO

    [self mvvm_observe:DW_KEYPATH(self, model.balanceModel)
                  with:^(typeof(self) self, id value) {
                      [self reloadAttributedData];
                  }];

    [self mvvm_observe:DW_KEYPATH(self, model.balanceDisplayOptions.balanceHidden)
                  with:^(typeof(self) self, NSNumber *value) {
                      [self hideBalance:self.model.balanceDisplayOptions.balanceHidden];
                  }];

    [self mvvm_observe:DW_KEYPATH(self, model.syncModel.state)
                  with:^(typeof(self) self, NSNumber *value) {
                      [self updateBalanceTitle];
                  }];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

#pragma mark - Actions

- (IBAction)balanceButtonAction:(UIControl *)sender {
    id<DWBalanceDisplayOptionsProtocol> balanceDisplayOptions = self.model.balanceDisplayOptions;
    balanceDisplayOptions.balanceHidden = !balanceDisplayOptions.balanceHidden;
}

- (void)balanceLongPressAction:(UIControl *)sender {
    [self.delegate balanceView:self balanceLongPressAction:sender];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIColor *balanceColor = [UIColor dw_lightTitleColor];
    DWBalanceModel *balanceModel = self.model.balanceModel;
    UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle1];

    self.dashBalanceLabel.attributedText = [balanceModel dashAmountStringWithFont:font
                                                                        tintColor:balanceColor];
    self.fiatBalanceLabel.text = [balanceModel fiatAmountString];
    self.fiatBalanceLabel.hidden = balanceModel == nil;
}

- (void)hideBalance:(BOOL)hidden {
    const BOOL animated = self.window != nil;

    [UIView animateWithDuration:animated ? ANIMATION_DURATION : 0.0
                     animations:^{
                         self.hidingView.alpha = hidden ? 1.0 : 0.0;
                         self.amountsView.alpha = hidden ? 0.0 : 1.0;

                         self.tapToUnhideLabel.text = hidden
                                                          ? NSLocalizedString(@"Tap to unhide balance", nil)
                                                          : NSLocalizedString(@"Tap to hide balance", nil);

                         [self updateBalanceTitle];
                     }];
}

- (void)updateBalanceTitle {
    if (self.model.balanceDisplayOptions.balanceHidden) {
        self.titleLabel.text = NSLocalizedString(@"Balance hidden", nil);
    }
    else {
        switch (self.model.syncModel.state) {
            case DWSyncModelState_Syncing:
                self.titleLabel.text = NSLocalizedString(@"Syncing Balance", nil);
                break;
            default:
                self.titleLabel.text = NSLocalizedString(@"Available balance", nil);
                break;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
