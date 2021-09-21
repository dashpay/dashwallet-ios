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

#import "DWAmountInputControl.h"

#import "DWUIKit.h"
#import "UIView+DWFindConstraints.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const BigAmountTextAlpha = 1.0;
static CGFloat const SmallAmountTextAlpha = 0.47; // same as #787878

static CGFloat const ViewHeight(BOOL small) {
    // 118 = ConvertImageTopPadding + ConvertImageBottomPadding + AmountHeight * 2
    return small ? 82.0 : 118.0;
}

static CGFloat const ConvertImageTopPadding(BOOL small) {
    return small ? 13.0 : 14.0;
}

static CGFloat const ConvertImageBottomPadding(BOOL small) {
    return small ? 7.0 : 16.0;
}

static CGFloat MainAmountFontSize(BOOL small) {
    return small ? 20.0 : 34.0;
}

static CGFloat SupplementaryAmountFontSize(BOOL small) {
    return small ? 11.0 : 17.0;
}

static CGFloat AmountHeight(BOOL small) {
    return small ? 24.0 : 44.0;
}

@interface DWAmountInputControl ()

@property (strong, nonatomic) IBOutlet UIControl *contentView;
@property (strong, nonatomic) IBOutlet UILabel *mainAmountLabel;
@property (strong, nonatomic) IBOutlet UIImageView *convertAmountImageView;
@property (strong, nonatomic) IBOutlet UILabel *supplementaryAmountLabel;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *mainAmountLabelCenterYConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *supplementaryAmountLabelCenterYConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *mainAlignmentViewHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *supplementaryAlignmentViewHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *mainAmountLabelHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *supplementaryAmountLabelHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *convertAmountImageViewTopConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *convertAmountImageViewBottomConstraint;
@property (strong, nonatomic) NSLayoutConstraint *contentViewHeightConstraint;
@property (strong, nonatomic) UIButton *selectorButton;

@end

@implementation DWAmountInputControl

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
        (self.contentViewHeightConstraint = [self.contentView.heightAnchor constraintEqualToConstant:ViewHeight(self.smallSize)]),
    ]];

    [self.contentView addTarget:self action:@selector(switchAmountCurrencyAction:) forControlEvents:UIControlEventTouchUpInside];

    self.smallSize = NO;
}

- (void)setSource:(id<DWAmountInputControlSource>)source {
    _source = source;

    self.mainAmountLabel.attributedText = source.dashAttributedString;
    self.supplementaryAmountLabel.attributedText = source.localCurrencyAttributedString;
}

- (void)setSmallSize:(BOOL)smallSize {
    _smallSize = smallSize;

    self.contentViewHeightConstraint.constant = ViewHeight(smallSize);
    self.mainAmountLabel.font = [UIFont dw_regularFontOfSize:MainAmountFontSize(smallSize)];
    self.supplementaryAmountLabel.font = [UIFont dw_regularFontOfSize:SupplementaryAmountFontSize(smallSize)];
    self.mainAlignmentViewHeightConstraint.constant = AmountHeight(smallSize);
    self.mainAmountLabelHeightConstraint.constant = AmountHeight(smallSize);
    self.supplementaryAlignmentViewHeightConstraint.constant = AmountHeight(smallSize);
    self.supplementaryAmountLabelHeightConstraint.constant = AmountHeight(smallSize);
    self.convertAmountImageViewTopConstraint.constant = ConvertImageTopPadding(smallSize);
    self.convertAmountImageViewBottomConstraint.constant = ConvertImageBottomPadding(smallSize);

    if (smallSize == NO && self.selectorButton == nil) {
        UIView *dummyView = [[UIView alloc] init];
        dummyView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:dummyView];

        self.selectorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.selectorButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.selectorButton setImage:[UIImage imageNamed:@"icon_selector"] forState:UIControlStateNormal];
        self.selectorButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [self.selectorButton addTarget:self action:@selector(selectorButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.selectorButton];

        NSLayoutConstraint *labelTrailing = [self.supplementaryAmountLabel dw_findConstraintWithAttribute:NSLayoutAttributeTrailing];
        labelTrailing.active = NO;

        NSLayoutConstraint *labelLeading = [self.supplementaryAmountLabel dw_findConstraintWithAttribute:NSLayoutAttributeLeading];
        labelLeading.active = NO;

        [NSLayoutConstraint activateConstraints:@[
            [dummyView.heightAnchor constraintEqualToConstant:42.0],
            [dummyView.widthAnchor constraintEqualToConstant:42.0],
            [dummyView.centerYAnchor constraintEqualToAnchor:self.supplementaryAmountLabel.centerYAnchor],
            [dummyView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.supplementaryAmountLabel.leadingAnchor constraintEqualToAnchor:dummyView.trailingAnchor],

            [self.selectorButton.heightAnchor constraintEqualToConstant:42.0],
            [self.selectorButton.widthAnchor constraintEqualToConstant:42.0],
            [self.selectorButton.leadingAnchor constraintEqualToAnchor:self.supplementaryAmountLabel.trailingAnchor],
            [self.selectorButton.centerYAnchor constraintEqualToAnchor:self.supplementaryAmountLabel.centerYAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.selectorButton.trailingAnchor],
        ]];

        // Initial scaling
        const CGFloat scale = SupplementaryAmountFontSize(smallSize) / MainAmountFontSize(smallSize);
        self.selectorButton.transform = CGAffineTransformMakeScale(scale, scale);
    }
}

- (void)setControlColor:(UIColor *)controlColor {
    _controlColor = controlColor;

    self.mainAmountLabel.textColor = controlColor;
    self.supplementaryAmountLabel.textColor = controlColor;
    self.convertAmountImageView.tintColor = controlColor;
}

- (void)setActiveTypeAnimated:(DWAmountType)activeType completion:(void (^)(void))completion {
    const BOOL wasSwapped = activeType != DWAmountTypeSupplementary;
    const BOOL smallSize = self.smallSize;
    UILabel *bigLabel = nil;
    UILabel *smallLabel = nil;
    if (wasSwapped) {
        bigLabel = self.supplementaryAmountLabel;
        smallLabel = self.mainAmountLabel;
    }
    else {
        bigLabel = self.mainAmountLabel;
        smallLabel = self.supplementaryAmountLabel;
    }
    const CGFloat scale = SupplementaryAmountFontSize(smallSize) / MainAmountFontSize(smallSize);
    bigLabel.font = [UIFont dw_regularFontOfSize:SupplementaryAmountFontSize(smallSize)];
    bigLabel.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale);
    smallLabel.font = [UIFont dw_regularFontOfSize:MainAmountFontSize(smallSize)];
    smallLabel.transform = CGAffineTransformMakeScale(scale, scale);
    self.selectorButton.transform = wasSwapped ? smallLabel.transform : CGAffineTransformIdentity;

    [UIView animateWithDuration:0.1
        delay:0.0
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
            bigLabel.alpha = SmallAmountTextAlpha;
            smallLabel.alpha = BigAmountTextAlpha;
            bigLabel.transform = CGAffineTransformIdentity;
            smallLabel.transform = CGAffineTransformIdentity;
        }
        completion:^(BOOL finished) {
            const CGFloat labelHeight = CGRectGetHeight(bigLabel.bounds);
            const CGFloat maxY = MAX(CGRectGetMaxY(bigLabel.frame), CGRectGetMaxY(smallLabel.frame));
            const CGFloat translation = maxY - labelHeight;
            self.mainAmountLabelCenterYConstraint.constant = wasSwapped ? 0.0 : translation;
            self.supplementaryAmountLabelCenterYConstraint.constant = wasSwapped ? 0.0 : -translation;
            [UIView animateWithDuration:0.7
                                  delay:0.0
                 usingSpringWithDamping:0.5
                  initialSpringVelocity:1.0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 [self layoutIfNeeded];
                             }
                             completion:nil];
            [UIView animateWithDuration:0.4
                animations:^{
                    self.convertAmountImageView.transform = (wasSwapped ? CGAffineTransformIdentity : CGAffineTransformMakeRotation(0.9999 * M_PI));
                }
                completion:^(BOOL finished) {
                    if (completion) {
                        completion();
                    }
                }];
        }];
}

#pragma mark - Private

- (void)switchAmountCurrencyAction:(id)sender {
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)selectorButtonAction:(UIButton *)sender {
    [self.delegate amountInputControl:self currencySelectorAction:sender];
}

@end

NS_ASSUME_NONNULL_END
