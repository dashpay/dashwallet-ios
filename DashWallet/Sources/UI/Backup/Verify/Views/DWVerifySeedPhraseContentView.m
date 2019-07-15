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

#import "DWVerifySeedPhraseContentView.h"

#import "DWSeedPhraseTitledView.h"
#import "DWSeedPhraseView.h"
#import "UIColor+DWStyle.h"

static CGFloat const DEFAULT_PADDING = 64.0;
static CGFloat const COMPACT_PADDING = 16.0;
static CGFloat const BOTTOM_PADDING = 12.0;

static CGSize const CLEAR_BUTTON_SIZE = { 110.0, 50.0 };

NS_ASSUME_NONNULL_BEGIN

@interface DWVerifySeedPhraseContentView ()

@property (nonatomic, strong) DWSeedPhraseTitledView *previewSeedPhraseView;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) DWSeedPhraseView *selectSeedPhraseView;

@property (nonatomic, strong) NSLayoutConstraint *previewSeedPhraseTopConstraint;

@end

@implementation DWVerifySeedPhraseContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWSeedPhraseTitledView *previewSeedPhraseView = [[DWSeedPhraseTitledView alloc] initWithType:DWSeedPhraseType_Preview];
        previewSeedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:previewSeedPhraseView];
        _previewSeedPhraseView = previewSeedPhraseView;

        UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        clearButton.translatesAutoresizingMaskIntoConstraints = NO;
        clearButton.tintColor = [UIColor dw_dashBlueColor];
        [clearButton setImage:[UIImage imageNamed:@"backspace"] forState:UIControlStateNormal];
        [clearButton addTarget:self action:@selector(clearButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:clearButton];

        _previewSeedPhraseTopConstraint = [previewSeedPhraseView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                                                          constant:COMPACT_PADDING];

        [NSLayoutConstraint activateConstraints:@[
            _previewSeedPhraseTopConstraint,
            [previewSeedPhraseView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [previewSeedPhraseView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [clearButton.topAnchor constraintEqualToAnchor:previewSeedPhraseView.bottomAnchor],
            [clearButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [clearButton.widthAnchor constraintEqualToConstant:CLEAR_BUTTON_SIZE.width],
            [clearButton.heightAnchor constraintEqualToConstant:CLEAR_BUTTON_SIZE.height],
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

#pragma mark - Actions

- (void)clearButtonAction:(id)sender {
    
}

@end

NS_ASSUME_NONNULL_END
