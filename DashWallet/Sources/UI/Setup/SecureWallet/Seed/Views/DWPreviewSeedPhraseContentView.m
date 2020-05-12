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

#import "DWPreviewSeedPhraseContentView.h"

#import "DWBlueActionButton.h"
#import "DWCheckbox.h"
#import "DWSeedPhraseTitledView.h"
#import "DWSeedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const CONFIRMATION_SHOW_DELAY = 2.0;
static NSTimeInterval const ANIMATION_DURATION = 0.3;
static NSTimeInterval const SCREENSHOT_ERROR_MSG_DELAY = 5.0;
static CGFloat const PHRASE_WARNING_PADDING = 36.0;

@interface DWPreviewSeedPhraseContentView ()

@property (nonatomic, strong) DWSeedPhraseTitledView *seedPhraseView;
@property (nonatomic, strong) DWCheckbox *confirmationCheckbox;
@property (nonatomic, strong) UIStackView *screenshotWarningStackView;
@property (nonatomic, strong) DWBlueActionButton *screenshotDescriptionButton;

@property (nonatomic, strong) NSLayoutConstraint *seedPhraseTopConstraint;

@property (nonatomic, assign) BOOL initialAnimationCompleted;

@end

@implementation DWPreviewSeedPhraseContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWSeedPhraseTitledView *seedPhraseView = [[DWSeedPhraseTitledView alloc] initWithType:DWSeedPhraseType_Preview];
        seedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:seedPhraseView];
        _seedPhraseView = seedPhraseView;

        DWCheckbox *confirmationCheckbox = [[DWCheckbox alloc] initWithFrame:CGRectZero];
        confirmationCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
        confirmationCheckbox.title = NSLocalizedString(@"I wrote it down", nil);
        confirmationCheckbox.alpha = 0.0;
        [confirmationCheckbox addTarget:self
                                 action:@selector(confirmationCheckboxAction:)
                       forControlEvents:UIControlEventValueChanged];
        [self addSubview:confirmationCheckbox];
        _confirmationCheckbox = confirmationCheckbox;

        UIImageView *warningImageView = [[UIImageView alloc] init];
        warningImageView.translatesAutoresizingMaskIntoConstraints = NO;
        warningImageView.image = [UIImage imageNamed:@"icon_screenshot_warning"];

        UILabel *warningLabel = [[UILabel alloc] init];
        warningLabel.translatesAutoresizingMaskIntoConstraints = NO;
        warningLabel.numberOfLines = 0;
        warningLabel.textAlignment = NSTextAlignmentCenter;
        warningLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        warningLabel.adjustsFontForContentSizeCategory = YES;
        warningLabel.textColor = [UIColor dw_redColor];
        warningLabel.text = [NSString stringWithFormat:@"%@\n%@",
                                                       NSLocalizedString(@"WARNING", nil),
                                                       NSLocalizedString(@"Do not take a screenshot", nil)];

        UIStackView *screenshotWarningStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ warningImageView, warningLabel ]];
        screenshotWarningStackView.translatesAutoresizingMaskIntoConstraints = NO;
        screenshotWarningStackView.axis = UILayoutConstraintAxisVertical;
        screenshotWarningStackView.alignment = UIStackViewAlignmentCenter;
        screenshotWarningStackView.spacing = 16.0;
        [self addSubview:screenshotWarningStackView];
        _screenshotWarningStackView = screenshotWarningStackView;

        DWBlueActionButton *screenshotDescriptionButton = [[DWBlueActionButton alloc] init];
        screenshotDescriptionButton.translatesAutoresizingMaskIntoConstraints = NO;
        screenshotDescriptionButton.inverted = YES;
        screenshotDescriptionButton.small = YES;
        [screenshotDescriptionButton setTitle:NSLocalizedString(@"Why I should not take a screenshot?", nil) forState:UIControlStateNormal];
        [screenshotDescriptionButton addTarget:self action:@selector(screenshotDescriptionButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:screenshotDescriptionButton];
        _screenshotDescriptionButton = screenshotDescriptionButton;

#if SNAPSHOT
        confirmationCheckbox.accessibilityIdentifier = @"seedphrase_checkbox";
#endif /* SNAPSHOT */

        _seedPhraseTopConstraint = [seedPhraseView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                                            constant:DW_TOP_COMPACT_PADDING];

        [NSLayoutConstraint activateConstraints:@[
            _seedPhraseTopConstraint,
            [seedPhraseView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [seedPhraseView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [screenshotWarningStackView.topAnchor constraintEqualToAnchor:seedPhraseView.bottomAnchor
                                                                 constant:PHRASE_WARNING_PADDING],
            [screenshotWarningStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:screenshotWarningStackView.trailingAnchor],


            [confirmationCheckbox.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [confirmationCheckbox.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
            [confirmationCheckbox.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.trailingAnchor],
            [confirmationCheckbox.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                              constant:-DW_BOTTOM_PADDING],

            [screenshotDescriptionButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:screenshotDescriptionButton.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:screenshotDescriptionButton.bottomAnchor
                                              constant:DW_BOTTOM_PADDING],
            [screenshotDescriptionButton.heightAnchor constraintEqualToConstant:44.0],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (!CGSizeEqualToSize(self.bounds.size, [self intrinsicContentSize])) {
        [self invalidateIntrinsicContentSize];
    }
}

- (CGSize)intrinsicContentSize {
    const CGFloat height = self.seedPhraseTopConstraint.constant +
                           [self minimumContentHeightWithoutTopPadding];

    return CGSizeMake(self.visibleSize.width, MAX(height, self.visibleSize.height));
}

- (nullable DWSeedPhraseModel *)model {
    return self.seedPhraseView.model;
}

- (void)setModel:(nullable DWSeedPhraseModel *)model {
    self.seedPhraseView.model = model;
}

- (void)setDisplayType:(DWSeedPhraseDisplayType)displayType {
    _displayType = displayType;

    switch (displayType) {
        case DWSeedPhraseDisplayType_Backup: {
            self.confirmationCheckbox.hidden = NO;
            self.screenshotDescriptionButton.hidden = YES;
            self.screenshotWarningStackView.hidden = YES;
            self.seedPhraseView.title = NSLocalizedString(@"Please write it down", nil);

            break;
        }
        case DWSeedPhraseDisplayType_Preview: {
            self.confirmationCheckbox.hidden = YES;
            self.screenshotDescriptionButton.hidden = NO;
            self.screenshotWarningStackView.hidden = NO;
            self.seedPhraseView.title = @"";

            break;
        }
    }
}

- (void)setVisibleSize:(CGSize)visibleSize {
    _visibleSize = visibleSize;

    const CGFloat contentHeight = DW_TOP_COMPACT_PADDING + [self minimumContentHeightWithoutTopPadding];
    if (visibleSize.height - contentHeight >= DW_TOP_DEFAULT_PADDING * 2.0) {
        self.seedPhraseTopConstraint.constant = DW_TOP_DEFAULT_PADDING;
    }
    else {
        self.seedPhraseTopConstraint.constant = DW_TOP_COMPACT_PADDING;
    }

    [self setNeedsLayout];
}

- (void)viewWillAppear {
    if (!self.initialAnimationCompleted) {
        [self.seedPhraseView prepareForAppearanceAnimation];
        [self showConfirmationCheckBoxAfterDelay];
    }
    self.initialAnimationCompleted = YES;
}

- (void)viewDidAppear {
    [self.seedPhraseView showSeedPhraseAnimated];
}

- (void)updateSeedPhraseModelAnimated:(DWSeedPhraseModel *)seedPhrase {
    [self.seedPhraseView updateSeedPhraseModelAnimated:seedPhrase];

    // reset confirmation checkbox
    self.confirmationCheckbox.on = NO;
    self.confirmationCheckbox.alpha = 0.0;
    [self showConfirmationCheckBoxAfterDelay];
}

- (void)showScreenshotDetectedErrorMessage {
    self.seedPhraseView.title = NSLocalizedString(@"Screenshot detected. New recovery phrase:", nil);
    self.seedPhraseView.titleStyle = DWSeedPhraseTitledViewTitleStyle_Error;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCREENSHOT_ERROR_MSG_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.seedPhraseView.title = NSLocalizedString(@"Please write it down", nil);
        weakSelf.seedPhraseView.titleStyle = DWSeedPhraseTitledViewTitleStyle_Default;
    });
}

- (CGFloat)minimumContentHeightWithoutTopPadding {
    CGFloat contentHeight = self.seedPhraseView.intrinsicContentSize.height +
                            DW_TOP_COMPACT_PADDING +
                            self.confirmationCheckbox.intrinsicContentSize.height +
                            DW_BOTTOM_PADDING;

    if (!self.screenshotWarningStackView.hidden) {
        contentHeight += self.screenshotWarningStackView.intrinsicContentSize.height;
    }

    return contentHeight;
}

#pragma mark - Actions

- (void)confirmationCheckboxAction:(DWCheckbox *)sender {
    [self.delegate previewSeedPhraseContentView:self didChangeConfirmation:sender.isOn];
}

- (void)screenshotDescriptionButtonAction {
    [self.delegate previewSeedPhraseContentViewShowScreenshotDescription:self];
}

#pragma mark - Private

- (void)showConfirmationCheckBoxAfterDelay {
    // Use weak here in case when user poped screen before timer fires
    __weak typeof(self) weakSelf = self;
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CONFIRMATION_SHOW_DELAY * NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:ANIMATION_DURATION
                         animations:^{
                             weakSelf.confirmationCheckbox.alpha = 1.0;
                         }];
    });
}

@end

NS_ASSUME_NONNULL_END
