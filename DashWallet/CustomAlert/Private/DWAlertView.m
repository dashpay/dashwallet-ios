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

#import "DWAlertView.h"

#import "DWActionsStackView.h"
#import "DWAlertAction.h"
#import "DWAlertInternalConstants.h"
#import "DWDimmingView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAlertView () <DWActionsStackViewDelegate>

@property (strong, nonatomic) UIVisualEffectView *vibrancyEffectView;
@property (strong, nonatomic) UIView *contentView;
@property (strong, nonatomic) DWActionsStackView *actionsStackView;
@property (strong, nonatomic) NSLayoutConstraint *actionsStackViewHeightConstraint;
@property (strong, nonatomic) UIView *actionTouchHighlightView;
@property (strong, nonatomic) DWDimmingView *separatorView;

@end

@implementation DWAlertView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = DWAlertViewCornerRadius;
        self.layer.masksToBounds = YES;

        UIView *whiteView = [[UIView alloc] initWithFrame:self.bounds];
        whiteView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        whiteView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        [self addSubview:whiteView];

        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];
        UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurEffectView.frame = self.bounds;
        blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:blurEffectView];

        UIVibrancyEffect *vibrancyEffect = [UIVibrancyEffect effectForBlurEffect:blurEffect];
        UIVisualEffectView *vibrancyEffectView = [[UIVisualEffectView alloc] initWithEffect:vibrancyEffect];
        vibrancyEffectView.frame = blurEffectView.contentView.bounds;
        vibrancyEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [blurEffectView.contentView addSubview:vibrancyEffectView];
        _vibrancyEffectView = vibrancyEffectView;

        UIView *vibrancyContentView = vibrancyEffectView.contentView;

        DWDimmingView *separatorView = [[DWDimmingView alloc] initWithFrame:vibrancyContentView.bounds];
        separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        separatorView.inverted = YES;
        separatorView.dimmingColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        separatorView.dimmingOpacity = 1.0;
        [vibrancyContentView addSubview:separatorView];
        _separatorView = separatorView;

        UIView *actionTouchHighlightView = [[UIView alloc] initWithFrame:CGRectZero];
        actionTouchHighlightView.backgroundColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        [vibrancyContentView addSubview:actionTouchHighlightView];
        _actionTouchHighlightView = actionTouchHighlightView;

        DWActionsStackView *actionsStackView = [[DWActionsStackView alloc] initWithFrame:CGRectZero];
        actionsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        actionsStackView.delegate = self;
        [self addSubview:actionsStackView];
        [NSLayoutConstraint activateConstraints:@[
            [actionsStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [actionsStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [actionsStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            (_actionsStackViewHeightConstraint = [actionsStackView.heightAnchor constraintEqualToConstant:0.0]),
        ]];
        _actionsStackView = actionsStackView;

        UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:contentView];
        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:actionsStackView.topAnchor constant:-DWAlertViewSeparatorSize()],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
        _contentView = contentView;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self updateActionsSeparatorsLayout];
}

#pragma mark - Public

- (nullable DWAlertAction *)preferredAction {
    return self.actionsStackView.preferredAction;
}

- (void)setPreferredAction:(nullable DWAlertAction *)preferredAction {
    self.actionsStackView.preferredAction = preferredAction;
}

- (void)addAction:(DWAlertAction *)action {
    DWAlertViewActionButton *button = [[DWAlertViewActionButton alloc] initWithAlertAction:action];
    [self.actionsStackView addActionButton:button];
}

- (void)resetActionsState {
    [self.actionsStackView resetActionsState];
}

- (void)removeAllActions {
    [self.actionsStackView removeAllActions];
}

#pragma mark - DWActionsStackViewDelegate

- (void)actionsStackViewDidUpdateLayout:(DWActionsStackView *)view {
    if (self.actionsStackView.axis == UILayoutConstraintAxisHorizontal) {
        self.actionsStackViewHeightConstraint.constant = DWAlertViewActionButtonHeight;
    }
    else {
        NSUInteger actionsCount = self.actionsStackView.arrangedSubviews.count;
        CGFloat constant = actionsCount * DWAlertViewActionButtonHeight + (actionsCount - 1) * DWAlertViewSeparatorSize();
        self.actionsStackViewHeightConstraint.constant = constant;
    }

    [self updateActionsSeparators];
}

- (void)actionsStackView:(DWActionsStackView *)view didAction:(DWAlertAction *)action {
    [self.delegate alertView:self didAction:action];
}

- (void)actionsStackView:(DWActionsStackView *)view highlightActionAtRect:(CGRect)rect {
    CGRect rectInAlertView = [self convertRect:rect fromView:self.actionsStackView];
    self.actionTouchHighlightView.frame = rectInAlertView;
}

#pragma mark - Private

- (void)updateActionsSeparators {
    NSUInteger actionsCount = self.actionsStackView.arrangedSubviews.count;
    if (actionsCount == 1) {
        return;
    }

    [self setNeedsLayout];
}

- (void)updateActionsSeparatorsLayout {
    NSUInteger actionsCount = self.actionsStackView.arrangedSubviews.count;
    if (actionsCount == 0) {
        self.separatorView.hidden = YES;

        return;
    }

    self.separatorView.hidden = NO;

    CGFloat separatorSize = DWAlertViewSeparatorSize();
    CGFloat actionsHeight = self.actionsStackViewHeightConstraint.constant;
    CGSize size = self.bounds.size;

    CGRect contentActionsSeparator = CGRectMake(0.0, size.height - (actionsHeight + separatorSize), size.width, separatorSize);
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:contentActionsSeparator];

    NSUInteger separatorsCount = actionsCount - 1;
    CGFloat y = CGRectGetMinY(contentActionsSeparator);

    if (self.actionsStackView.axis == UILayoutConstraintAxisHorizontal) {
        CGFloat distance = size.width / actionsCount - separatorSize * separatorsCount;
        CGFloat x = distance;
        for (NSUInteger i = 0; i < separatorsCount; i++) {
            CGRect separator = CGRectMake(x, y, separatorSize, DWAlertViewActionButtonHeight);
            [path appendPath:[UIBezierPath bezierPathWithRect:separator]];
            x += distance + separatorSize;
        }
    }
    else {
        CGFloat distance = actionsHeight / actionsCount - separatorSize * separatorsCount;
        y += distance;
        for (NSUInteger i = 0; i < separatorsCount; i++) {
            CGRect separator = CGRectMake(0.0, y, size.width, separatorSize);
            [path appendPath:[UIBezierPath bezierPathWithRect:separator]];
            y += distance + separatorSize;
        }
    }

    self.separatorView.visiblePath = path;
}

@end

NS_ASSUME_NONNULL_END
