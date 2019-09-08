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

#import "DWAmountPreviewView.h"
#import "DWPaymentOutput.h"
#import "DWTitleDetailCellModel.h"
#import "DWTitleDetailCellView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmPaymentContentView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet DWAmountPreviewView *amountView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *infoRowView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *addressRowView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *feeRowView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *totalRowView;

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

    self.infoRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;
    self.addressRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;
    self.feeRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;
    self.totalRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)setPaymentOutput:(nullable DWPaymentOutput *)paymentOutput {
    _paymentOutput = paymentOutput;

    [self.amountView setAmount:[paymentOutput amountToDisplay]];

    NSString *_Nullable infoString = [paymentOutput generalInfoString];
    DWTitleDetailCellModel *info =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                title:nil
                                          plainDetail:infoString];

    self.infoRowView.model = info;
    self.infoRowView.hidden = (infoString == nil);

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];

    NSAttributedString *addressString = [self.paymentOutput addressAttributedStringWithFont:font];
    DWTitleDetailCellModel *address =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_TruncatedSingleLine
                                                title:NSLocalizedString(@"Pay to", nil)
                                     attributedDetail:addressString];
    self.addressRowView.model = address;

    NSAttributedString *_Nullable feeString = [self.paymentOutput networkFeeAttributedStringWithFont:font];
    DWTitleDetailCellModel *fee =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                title:NSLocalizedString(@"Network fee", nil)
                                     attributedDetail:feeString];
    self.feeRowView.model = fee;
    self.feeRowView.hidden = (feeString == nil);

    DWTitleDetailCellModel *total =
        [[DWTitleDetailCellModel alloc] initWithStyle:DWTitleDetailItem_Default
                                                title:NSLocalizedString(@"Total", nil)
                                     attributedDetail:[self.paymentOutput totalAttributedStringWithFont:font]];
    self.totalRowView.model = total;
}

@end

NS_ASSUME_NONNULL_END
