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

#import "DWTxDetailContentView.h"

#import "DWTitleDetailCellView.h"
#import "DWTxDetailModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxDetailContentView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *dashAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatAmountLabel;
@property (strong, nonatomic) IBOutlet UIButton *viewInExplorerButton;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *addressCellView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *feeCellView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *dateCellView;
@property (strong, nonatomic) IBOutlet UIButton *closeButton;

@end

@implementation DWTxDetailContentView

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

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.dashAmountLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    self.fiatAmountLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];

    [self.viewInExplorerButton setTitle:NSLocalizedString(@"View in Explorer", nil)
                               forState:UIControlStateNormal];
    [self.closeButton setTitle:NSLocalizedString(@"Close", nil)
                      forState:UIControlStateNormal];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)setDisplayType:(DWTxDetailDisplayType)displayType {
    _displayType = displayType;

    UIImage *iconImage = nil;
    NSString *title = nil;
    DWTitleDetailCellViewPadding contentPadding;
    switch (displayType) {
        case DWTxDetailDisplayType_Sent: {
            iconImage = [UIImage imageNamed:@"icon_tx_sent"];
            title = NSLocalizedString(@"Amount Sent", nil);
            contentPadding = DWTitleDetailCellViewPadding_Small;

            break;
        }
        case DWTxDetailDisplayType_Received: {
            iconImage = [UIImage imageNamed:@"icon_tx_received"];
            title = NSLocalizedString(@"Amount Received", nil);
            contentPadding = DWTitleDetailCellViewPadding_Small;

            break;
        }
        case DWTxDetailDisplayType_Paid: {
            iconImage = [UIImage imageNamed:@"icon_tx_paid"];
            title = NSLocalizedString(@"Paid successfully", nil);
            contentPadding = DWTitleDetailCellViewPadding_None;

            break;
        }
    }

    NSParameterAssert(iconImage);

    self.iconImageView.image = iconImage;
    self.titleLabel.text = title;

    self.addressCellView.contentPadding = contentPadding;
    self.feeCellView.contentPadding = contentPadding;
    self.dateCellView.contentPadding = contentPadding;
}

- (void)setModel:(nullable DWTxDetailModel *)model {
    _model = model;

    self.fiatAmountLabel.text = model.fiatAmountString;
    self.dateCellView.model = model.date;

    [self reloadAttributedData];
}

#pragma mark - Actions

- (IBAction)viewInExplorerButtonAction:(UIButton *)sender {
    [self.delegate txDetailContentView:self viewInExplorerButtonAction:sender];
}

- (IBAction)closeButtonAction:(UIButton *)sender {
    [self.delegate txDetailContentView:self closeButtonAction:sender];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    DWTxDetailModel *model = self.model;

    UIFont *amountFont = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    self.dashAmountLabel.attributedText = [model dashAmountStringWithFont:amountFont];

    UIFont *detailFont = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    self.addressCellView.model = [model addressWithFont:detailFont];

    id<DWTitleDetailItem> feeModel = [model feeWithFont:detailFont tintColor:[UIColor dw_secondaryTextColor]];
    self.feeCellView.model = feeModel;
    self.feeCellView.hidden = (feeModel == nil);
}

@end

NS_ASSUME_NONNULL_END
