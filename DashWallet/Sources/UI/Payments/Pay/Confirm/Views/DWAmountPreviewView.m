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

#import "DWAmountPreviewView.h"

#import <DashSync/DashSync.h>

#import "DWUIKit.h"
#import "NSAttributedString+DWBuilder.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const DashSymbolMainSize = {35.0, 27.0};

@interface DWAmountPreviewView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UILabel *mainAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *supplementaryAmountLabel;

@end

@implementation DWAmountPreviewView

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

    // These two labels doesn't support Dynamic Type and have same hardcoded values as in DWAmountInputControl
    self.mainAmountLabel.font = [UIFont dw_regularFontOfSize:34.0];
    self.supplementaryAmountLabel.font = [UIFont dw_regularFontOfSize:16.0];
}

- (void)setAmount:(uint64_t)amount {
    self.mainAmountLabel.attributedText = [self mainAmountAttributedStringForAmount:amount];
    self.supplementaryAmountLabel.text = [self supplementaryAmountStringForAmount:amount];
}

#pragma mark - Private

- (NSAttributedString *)mainAmountAttributedStringForAmount:(uint64_t)amount {
    return [NSAttributedString dw_dashAttributedStringForAmount:amount
                                                      tintColor:[UIColor dw_darkTitleColor]
                                                     symbolSize:DashSymbolMainSize];
}

- (NSString *)supplementaryAmountStringForAmount:(uint64_t)amount {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *supplementaryAmount = [priceManager localCurrencyStringForDashAmount:amount];

    return supplementaryAmount;
}

@end

NS_ASSUME_NONNULL_END
