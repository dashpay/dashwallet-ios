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

#import "DWTitleDetailCellView.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmPaymentContentView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet DWAmountPreviewView *amountView;
@property (strong, nonatomic) IBOutlet DWTitleDetailCellView *nameRowView;
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

    self.nameRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Hidden;
    self.infoRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;
    self.addressRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;
    self.feeRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;
    self.totalRowView.separatorPosition = DWTitleDetailCellViewSeparatorPosition_Top;

    UILongPressGestureRecognizer *recognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(addressLongPressGestureAction:)];
    [self.addressRowView addGestureRecognizer:recognizer];


    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)setModel:(nullable id<DWConfirmPaymentViewProtocol>)model {
    _model = model;

    [self.amountView setAmount:[model amountToDisplay]];

    id<DWTitleDetailItem> name = [model nameInfo];
    self.nameRowView.model = name;
    self.nameRowView.hidden = (name == nil);

    id<DWTitleDetailItem> info = [model generalInfo];
    self.infoRowView.model = info;
    self.infoRowView.hidden = (info == nil);

    [self reloadAttributedData];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

#pragma mark - Actions

- (void)addressLongPressGestureAction:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) {
        return;
    }

    BOOL result = [self.model copyAddressToPasteboard];
    if (result) {
        [self dw_showInfoHUDWithText:NSLocalizedString(@"Copied", nil)];
    }
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    UIColor *color = [UIColor dw_secondaryTextColor];

    id<DWTitleDetailItem> address = [self.model addressWithFont:font tintColor:color];
    self.addressRowView.model = address;
    self.addressRowView.hidden = (address == nil);

    id<DWTitleDetailItem> fee = [self.model feeWithFont:font tintColor:color];
    self.feeRowView.model = fee;
    self.feeRowView.hidden = (fee == nil);

    self.totalRowView.model = [self.model totalWithFont:font tintColor:color];
}

@end

NS_ASSUME_NONNULL_END
