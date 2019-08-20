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

NS_ASSUME_NONNULL_BEGIN

static CGFloat const BigAmountTextAlpha = 1.0;
static CGFloat const SmallAmountTextAlpha = 0.43;

static CGFloat const ViewHeight(BOOL small) {
    return small ? 82.0 : 106.0;
}

static CGFloat const ConvertImageTopPadding(BOOL small) {
    return small ? 13.0 : 18.0;
}

static CGFloat const ConvertImageBottomPadding(BOOL small) {
    return small ? 7.0 : 10.0;
}

static CGFloat MainAmountFontSize(BOOL small) {
    return small ? 20.0 : 26.0;
}

static CGFloat SupplementaryAmountFontSize(BOOL small) {
    return small ? 11.0 : 14.0;
}

static CGFloat AmountHeight(BOOL small) {
    return small ? 24.0 : 32.0;
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
}

- (void)setSource:(id<DWAmountInputControlSource>)source {
    _source = source;

    self.mainAmountLabel.attributedText = source.dashAttributedString;
    self.supplementaryAmountLabel.attributedText = source.localCurrencyAttributedString;
}

- (void)setSmallSize:(BOOL)smallSize {
    _smallSize = smallSize;

    self.contentViewHeightConstraint.constant = ViewHeight(smallSize);
    self.mainAmountLabel.font = [UIFont systemFontOfSize:MainAmountFontSize(smallSize)];
    self.supplementaryAmountLabel.font = [UIFont systemFontOfSize:SupplementaryAmountFontSize(smallSize)];
    self.mainAlignmentViewHeightConstraint.constant = AmountHeight(smallSize);
    self.mainAmountLabelHeightConstraint.constant = AmountHeight(smallSize);
    self.supplementaryAlignmentViewHeightConstraint.constant = AmountHeight(smallSize);
    self.supplementaryAmountLabelHeightConstraint.constant = AmountHeight(smallSize);
    self.convertAmountImageViewTopConstraint.constant = ConvertImageTopPadding(smallSize);
    self.convertAmountImageViewBottomConstraint.constant = ConvertImageBottomPadding(smallSize);
}

- (void)setControlColor:(UIColor *)controlColor {
    _controlColor = controlColor;

    self.mainAmountLabel.textColor = controlColor;
    self.supplementaryAmountLabel.textColor = controlColor;
    self.convertAmountImageView.tintColor = controlColor;
}

- (void)setActiveTypeAnimated:(DWAmountType)activeType completion:(void (^)(void))completion {
    BOOL wasSwapped = activeType != DWAmountTypeSupplementary;
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
    CGFloat scale = SupplementaryAmountFontSize(self.smallSize) / MainAmountFontSize(self.smallSize);
    bigLabel.font = [UIFont systemFontOfSize:SupplementaryAmountFontSize(self.smallSize)];
    bigLabel.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale);
    smallLabel.font = [UIFont systemFontOfSize:MainAmountFontSize(self.smallSize)];
    smallLabel.transform = CGAffineTransformMakeScale(scale, scale);

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
            CGFloat labelHeight = CGRectGetHeight(bigLabel.bounds);
            CGFloat maxY = MAX(CGRectGetMaxY(bigLabel.frame), CGRectGetMaxY(smallLabel.frame));
            CGFloat translation = maxY - labelHeight;
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

@end

NS_ASSUME_NONNULL_END
