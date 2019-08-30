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

#import "DWConfirmPaymentContentView.h"

#import "DWConfirmPaymentRowView.h"
#import "DWPaymentOutput.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmPaymentContentView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UILabel *mainAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *supplementaryAmountLabel;
@property (strong, nonatomic) IBOutlet DWConfirmPaymentRowView *infoRowView;
@property (strong, nonatomic) IBOutlet DWConfirmPaymentRowView *addressRowView;
@property (strong, nonatomic) IBOutlet DWConfirmPaymentRowView *feeRowView;
@property (strong, nonatomic) IBOutlet DWConfirmPaymentRowView *totalRowView;

@end

@implementation DWConfirmPaymentContentView

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
    self.mainAmountLabel.font = [UIFont dw_lightFontOfSize:44.0];
    self.supplementaryAmountLabel.font = [UIFont dw_lightFontOfSize:18.0];

    self.infoRowView.titleLabel.hidden = YES;

    self.addressRowView.titleLabel.text = NSLocalizedString(@"Pay to", nil);
    self.feeRowView.titleLabel.text = NSLocalizedString(@"Network fee", nil);
    self.totalRowView.titleLabel.text = NSLocalizedString(@"Total", nil);

    self.addressRowView.detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.addressRowView.detailLabel.numberOfLines = 1;
    self.addressRowView.detailLabel.adjustsFontSizeToFitWidth = NO;
}

- (void)setPaymentOutput:(nullable DWPaymentOutput *)paymentOutput {
    self.mainAmountLabel.attributedText = [paymentOutput mainAmountAttributedString];
    self.supplementaryAmountLabel.text = [paymentOutput supplementaryAmountString];

    NSString *_Nullable info = [paymentOutput generalInfoString];
    self.infoRowView.detailLabel.text = info;
    self.infoRowView.hidden = (info == nil);

    self.addressRowView.detailLabel.text = paymentOutput.address;

    NSAttributedString *_Nullable fee = [paymentOutput networkFeeAttributedString];
    self.feeRowView.detailLabel.attributedText = fee;
    self.feeRowView.hidden = (fee == nil);

    self.totalRowView.detailLabel.attributedText = [paymentOutput totalAttributedString];
}

@end

NS_ASSUME_NONNULL_END
