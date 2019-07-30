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

#import "DWSeedWordView.h"

#import "DWSeedWordModel+DWLayoutSupport.h"
#import "DWSeedWordModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

NSTimeInterval const DW_VERIFY_APPEAR_ANIMATION_DURATION = 0.25;

static UIColor *BackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_dashBlueColor];
    }
}

static UIColor *TextBackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor clearColor];
    }
}

static UIColor *TextColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return [UIColor dw_dashBlueColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_lightTitleColor];
    }
}

static UIColor *SelectedBackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            NSCAssert(NO, @"DWSeedPhraseType_Preview / DWSeedPhraseType_Verify is not selectable");
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_disabledButtonColor];
    }
}

static UIFont *WordFont(DWSeedPhraseType type) {
    return [DWSeedWordModel dw_wordFontForType:type];
}

static CGFloat CornerRadius(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 0.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}

static BOOL MasksToBounds(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return NO;
        case DWSeedPhraseType_Select:
            return YES;
    }
}

static NSDictionary *TextAttributes(DWSeedPhraseType type) {
    NSDictionary *attributes = @{
        NSFontAttributeName : WordFont(type),
    };
    return attributes;
}

@interface DWSeedWordView ()

@property (readonly, nonatomic, assign) DWSeedPhraseType type;
@property (readonly, strong, nonatomic) UILabel *wordLabel;

@end

@implementation DWSeedWordView

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _type = type;

        self.layer.cornerRadius = CornerRadius(type);
        self.layer.masksToBounds = MasksToBounds(type);

        self.backgroundColor = BackgroundColor(type);

        UILabel *wordLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        wordLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        wordLabel.backgroundColor = TextBackgroundColor(type);
        wordLabel.textColor = TextColor(type);
        wordLabel.textAlignment = NSTextAlignmentCenter;
        wordLabel.adjustsFontForContentSizeCategory = YES;
        wordLabel.font = WordFont(type);
        wordLabel.numberOfLines = 0;
        wordLabel.adjustsFontSizeToFitWidth = YES; // protects from clipping text
        wordLabel.minimumScaleFactor = 0.5;
        [self addSubview:wordLabel];
        _wordLabel = wordLabel;

        if (type == DWSeedPhraseType_Verify) {
            [self mvvm_observe:DW_KEYPATH(self, model.visible)
                          with:^(typeof(self) self, NSNumber *value) {
                              if (!self.model) {
                                  return;
                              }

                              const BOOL isVisible = self.model.isVisible;
                              [UIView animateWithDuration:isVisible ? DW_VERIFY_APPEAR_ANIMATION_DURATION : 0.0
                                               animations:^{
                                                   self.wordLabel.alpha = isVisible ? 1.0 : 0.0;
                                               }];
                          }];
        }
        else if (type == DWSeedPhraseType_Select) {
            [self mvvm_observe:DW_KEYPATH(self, model.selected)
                          with:^(typeof(self) self, NSNumber *value) {
                              if (!self.model) {
                                  return;
                              }

                              self.selected = self.model.selected;
                          }];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.wordLabel.frame = self.bounds;
}

- (void)setModel:(nullable DWSeedWordModel *)model {
    _model = model;

    NSAssert(model.word.length > 0, @"Seed word cell is broken. It's crucially important!");

    NSDictionary *attributes = TextAttributes(self.type);
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:model.word
                                                                           attributes:attributes];
    self.wordLabel.attributedText = attributedString;

    self.selected = model.selected;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];

    DWSeedPhraseType type = self.type;
    if (type != DWSeedPhraseType_Select) {
        return;
    }

    self.backgroundColor = selected ? SelectedBackgroundColor(type) : BackgroundColor(type);
}

- (void)animateDiscardedSelectionWithCompletion:(void (^)(void))completion {
    [CATransaction begin];
    [CATransaction setCompletionBlock:completion];

    const CFTimeInterval shakeDuration = 0.35;
    const CFTimeInterval shakeBeginTime = 0.1;
    const CFTimeInterval firstPartDuration = shakeBeginTime + shakeDuration;
    const CFTimeInterval secondPartDuration = 0.1;

    CABasicAnimation *redColorAnimation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    redColorAnimation.fromValue = (id)[UIColor dw_dashBlueColor].CGColor;
    redColorAnimation.toValue = (id)[UIColor dw_redColor].CGColor;
    redColorAnimation.duration = shakeBeginTime;
    redColorAnimation.beginTime = 0.0;
    redColorAnimation.fillMode = kCAFillModeForwards;
    redColorAnimation.removedOnCompletion = NO;

    CAKeyframeAnimation *shakeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shakeAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    shakeAnimation.values = @[ @(-8), @(8), @(-6), @(6), @(-4), @(4), @(0) ];
    shakeAnimation.beginTime = shakeBeginTime;
    shakeAnimation.duration = shakeDuration;

    CABasicAnimation *blueColorAnimation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    blueColorAnimation.fromValue = (id)[UIColor dw_redColor].CGColor;
    blueColorAnimation.toValue = (id)[UIColor dw_dashBlueColor].CGColor;
    blueColorAnimation.duration = secondPartDuration;
    blueColorAnimation.beginTime = firstPartDuration;

    CAAnimationGroup *groupAnimation = [CAAnimationGroup animation];
    groupAnimation.animations = @[ redColorAnimation, shakeAnimation, blueColorAnimation ];
    groupAnimation.duration = firstPartDuration + secondPartDuration;

    [self.layer addAnimation:groupAnimation forKey:@"DWDiscardedSelectionAnimation"];

    [CATransaction commit];
}

@end

NS_ASSUME_NONNULL_END
