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
#import "DWAlertViewActionButton.h"
#import "DWDimmingView.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - UIView Category

@implementation UIView (DWAlertViewHelper)

- (UIView *)dw_findFirstResponder {
    if (self.isFirstResponder) {
        return self;
    }

    for (UIView *subView in self.subviews) {
        UIView *responder = [subView dw_findFirstResponder];
        if (responder) {
            return responder;
        }
    }

    return nil;
}

- (nullable NSLayoutConstraint *)dw_maxHeightConstraint {
    for (NSLayoutConstraint *constraint in self.constraints) {
        if (constraint.firstItem == self &&
            constraint.firstAttribute == NSLayoutAttributeHeight &&
            constraint.relation == NSLayoutRelationLessThanOrEqual &&
            constraint.secondItem == nil) {
            return constraint;
        }
    }
    return nil;
}

@end

#pragma mark - Alert View

static UIColor *BackgroundWhiteViewColor() {
    return [UIColor colorWithWhite:1.0 alpha:0.1];
}

static UIColor *SeparatorColor() {
    return [UIColor colorWithWhite:0.75 alpha:1.0];
}

static UIColor *ActionTouchHighlightColor() {
    return [UIColor colorWithWhite:0.6 alpha:1.0];
}

@interface DWAlertView () <DWActionsStackViewDelegate, UIScrollViewDelegate>

@property (strong, nonatomic) UIVisualEffectView *vibrancyEffectView;
@property (strong, nonatomic) UIScrollView *contentScrollView;
@property (strong, nonatomic) UIView *contentView;
@property (strong, nonatomic) UIScrollView *actionsScrollView;
@property (strong, nonatomic) DWActionsStackView *actionsStackView;
@property (strong, nonatomic) NSLayoutConstraint *actionsStackViewHeightConstraint;
@property (strong, nonatomic) UIView *contentActionsSeparatorView;
@property (strong, nonatomic) UIScrollView *effectsScrollView;
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
        whiteView.backgroundColor = BackgroundWhiteViewColor();
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

        UIView *contentActionsSeparatorView = [[UIView alloc] initWithFrame:CGRectZero];
        contentActionsSeparatorView.backgroundColor = SeparatorColor();
        [vibrancyContentView addSubview:contentActionsSeparatorView];
        _contentActionsSeparatorView = contentActionsSeparatorView;

        UIScrollView *effectsScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        [vibrancyContentView addSubview:effectsScrollView];
        _effectsScrollView = effectsScrollView;

        DWDimmingView *separatorView = [[DWDimmingView alloc] initWithFrame:CGRectZero];
        separatorView.inverted = YES;
        separatorView.dimmingColor = SeparatorColor();
        separatorView.dimmingOpacity = 1.0;
        [separatorView setPathAnimationsDisabled];
        [effectsScrollView addSubview:separatorView];
        _separatorView = separatorView;

        UIView *actionTouchHighlightView = [[UIView alloc] initWithFrame:CGRectZero];
        actionTouchHighlightView.backgroundColor = ActionTouchHighlightColor();
        [effectsScrollView addSubview:actionTouchHighlightView];
        _actionTouchHighlightView = actionTouchHighlightView;

        UIScrollView *actionsScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        actionsScrollView.delegate = self;
        [self addSubview:actionsScrollView];
        _actionsScrollView = actionsScrollView;

        DWActionsStackView *actionsStackView = [[DWActionsStackView alloc] initWithFrame:CGRectZero];
        actionsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        actionsStackView.delegate = self;
        [actionsScrollView addSubview:actionsStackView];
        _actionsStackView = actionsStackView;

        UIScrollView *contentScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        [self addSubview:contentScrollView];
        _contentScrollView = contentScrollView;

        UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentScrollView addSubview:contentView];
        _contentView = contentView;

        [NSLayoutConstraint activateConstraints:@[
            [actionsStackView.topAnchor constraintEqualToAnchor:actionsScrollView.topAnchor],
            [actionsStackView.leadingAnchor constraintEqualToAnchor:actionsScrollView.leadingAnchor],
            [actionsStackView.bottomAnchor constraintEqualToAnchor:actionsScrollView.bottomAnchor],
            [actionsStackView.trailingAnchor constraintEqualToAnchor:actionsScrollView.trailingAnchor],
            [actionsStackView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
            (_actionsStackViewHeightConstraint = [actionsStackView.heightAnchor constraintEqualToConstant:0.0]),

            [contentView.topAnchor constraintEqualToAnchor:contentScrollView.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:contentScrollView.leadingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:contentScrollView.bottomAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:contentScrollView.trailingAnchor],
            [contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.bounds);
    BOOL hasActions = self.actionsStackView.arrangedSubviews.count > 0;
    CGFloat separatorSize = DWAlertViewSeparatorSize();
    NSLayoutConstraint *heightConstraint = [self dw_maxHeightConstraint];
    NSAssert(heightConstraint, @"DWAlertView has invalid layout");
    CGFloat maxHeight = heightConstraint.constant;
    CGFloat contentHeight = [self.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    CGFloat actionsHeight = self.actionsStackViewHeightConstraint.constant;
    CGFloat maxContentHeight = maxHeight;
    if (hasActions) {
        maxContentHeight -= DWAlertViewActionsMultilineMinimumHeight;
    }
    CGFloat leftOverForActions;
    CGFloat contentScrollHeight;
    if (contentHeight < maxContentHeight) {
        contentScrollHeight = contentHeight;
        leftOverForActions = maxHeight - contentHeight - separatorSize;
    }
    else {
        contentScrollHeight = maxContentHeight;
        if (hasActions) {
            contentScrollHeight -= separatorSize;
        }
        leftOverForActions = maxHeight - contentHeight;
    }
    CGFloat actionsScrollHeight = MAX(MIN(actionsHeight, DWAlertViewActionsMultilineMinimumHeight),
                                      MIN(actionsHeight, leftOverForActions));

    CGRect contentScrollFrame = CGRectMake(0.0, 0.0, width, contentScrollHeight);
    CGRect actionsScrollFrame = CGRectMake(0.0, contentScrollHeight + separatorSize, width, actionsScrollHeight);
    BOOL shouldInvalidateIntrinsicContentSize = NO;
    if (!CGRectEqualToRect(self.contentScrollView.frame, contentScrollFrame)) {
        self.contentScrollView.frame = contentScrollFrame;
        shouldInvalidateIntrinsicContentSize = YES;
    }
    if (!CGRectEqualToRect(self.actionsScrollView.frame, actionsScrollFrame)) {
        self.actionsScrollView.frame = actionsScrollFrame;
        shouldInvalidateIntrinsicContentSize = YES;
    }

    self.contentScrollView.contentSize = CGSizeMake(width, contentHeight);
    self.actionsScrollView.contentSize = CGSizeMake(width, actionsHeight);

    [self updateSeparatorsLayoutIgnoringRect:CGRectZero];

    if (shouldInvalidateIntrinsicContentSize) {
        [self invalidateIntrinsicContentSize];
    }
}

- (CGSize)intrinsicContentSize {
    CGFloat height = CGRectGetHeight(self.contentScrollView.frame);
    BOOL hasActions = self.actionsStackView.arrangedSubviews.count > 0;
    if (hasActions) {
        height += DWAlertViewSeparatorSize() + CGRectGetHeight(self.actionsScrollView.frame);
    }

    return CGSizeMake(UIViewNoIntrinsicMetric, height);
}

- (nullable NSArray<UIKeyCommand *> *)keyCommands {
    if ([self.contentView dw_findFirstResponder] != nil) {
        return nil;
    }

    UIKeyCommand *enterKeyCommand = [UIKeyCommand keyCommandWithInput:@"\r"
                                                        modifierFlags:kNilOptions
                                                               action:@selector(enterKeyCommandAction:)];
    return @[ enterKeyCommand ];
}

#pragma mark - Public

- (Class)actionViewClass {
    if (!_actionViewClass) {
        _actionViewClass = [DWAlertViewActionButton class];
    }
    return _actionViewClass;
}

- (nullable DWAlertAction *)preferredAction {
    return self.actionsStackView.preferredAction;
}

- (void)setPreferredAction:(nullable DWAlertAction *)preferredAction {
    self.actionsStackView.preferredAction = preferredAction;
}

- (void)addAction:(DWAlertAction *)action {
    DWAlertViewActionBaseView *button = [[self.actionViewClass alloc] initWithAlertAction:action];
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

    [self setNeedsLayout];
}

- (void)actionsStackView:(DWActionsStackView *)view didAction:(DWAlertAction *)action {
    [self.delegate alertView:self didAction:action];
}

- (void)actionsStackView:(DWActionsStackView *)view highlightActionAtRect:(CGRect)rect {
    CGRect convertedRect = [self.effectsScrollView convertRect:rect fromView:self.actionsStackView];
    self.actionTouchHighlightView.frame = convertedRect;

    if (!CGRectEqualToRect(convertedRect, CGRectZero)) {
        CGFloat inset = DWAlertViewSeparatorSize() * 2.0;
        if (self.actionsStackView.axis == UILayoutConstraintAxisHorizontal) {
            convertedRect = CGRectInset(convertedRect, -inset, 0.0);
        }
        else {
            convertedRect = CGRectInset(convertedRect, 0.0, -inset);
        }
    }
    [self updateSeparatorsLayoutIgnoringRect:convertedRect];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // sync scrolling of actions and action separators underneath
    CGRect scrollViewBounds = scrollView.bounds;
    scrollViewBounds.origin.y = scrollView.contentOffset.y;
    self.effectsScrollView.bounds = scrollViewBounds;
}

#pragma mark - Private

- (void)updateSeparatorsLayoutIgnoringRect:(CGRect)ignoringRect {
    NSUInteger actionsCount = self.actionsStackView.arrangedSubviews.count;
    if (actionsCount == 0) {
        self.contentActionsSeparatorView.hidden = YES;
        self.effectsScrollView.hidden = YES;

        return;
    }

    CGSize size = self.bounds.size;
    CGFloat separatorSize = DWAlertViewSeparatorSize();

    self.contentActionsSeparatorView.hidden = NO;
    self.contentActionsSeparatorView.frame = CGRectMake(0.0, CGRectGetHeight(self.contentScrollView.frame), size.width, separatorSize);

    CGSize actionsContentSize = self.actionsScrollView.contentSize;
    self.effectsScrollView.hidden = NO;
    self.effectsScrollView.frame = self.actionsScrollView.frame;
    self.effectsScrollView.contentSize = actionsContentSize;
    self.separatorView.frame = CGRectMake(0.0, 0.0, actionsContentSize.width, actionsContentSize.height);

    NSUInteger separatorsCount = actionsCount - 1;
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat y = 0.0;
    if (self.actionsStackView.axis == UILayoutConstraintAxisHorizontal) {
        CGFloat distance = size.width / actionsCount - separatorSize * separatorsCount;
        CGFloat x = distance;
        for (NSUInteger i = 0; i < separatorsCount; i++) {
            CGRect separator = CGRectMake(x, y, separatorSize, DWAlertViewActionButtonHeight);
            if (!CGRectContainsRect(ignoringRect, separator)) {
                [path appendPath:[UIBezierPath bezierPathWithRect:separator]];
            }
            x += distance + separatorSize;
        }
    }
    else {
        y += DWAlertViewActionButtonHeight;
        for (NSUInteger i = 0; i < separatorsCount; i++) {
            CGRect separator = CGRectMake(0.0, y, size.width, separatorSize);
            if (!CGRectContainsRect(ignoringRect, separator)) {
                [path appendPath:[UIBezierPath bezierPathWithRect:separator]];
            }
            y += DWAlertViewActionButtonHeight + separatorSize;
        }
    }

    self.separatorView.visiblePath = path;
}

- (void)enterKeyCommandAction:(UIKeyCommand *)sender {
    if (!self.preferredAction || self.preferredAction.style == DWAlertActionStyleCancel) {
        return;
    }

    [self.delegate alertView:self didAction:self.preferredAction];
}

@end

NS_ASSUME_NONNULL_END
