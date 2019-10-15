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

#import "DWTxDetailHeaderView.h"

#import "DWSuccessfulTransactionAnimatedIconView.h"
#import "DWTxDetailModel.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxDetailHeaderView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIView *iconContentView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *dashAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatAmountLabel;
@property (strong, nonatomic) IBOutlet UIButton *viewInExplorerButton;

@property (strong, nonatomic) UIImageView *iconImageView;
@property (nonatomic, strong) DWSuccessfulTransactionAnimatedIconView *animatedIconView;

@end

@implementation DWTxDetailHeaderView

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

    [self setViewInExplorerDefaultTitle];
    UILongPressGestureRecognizer *recognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(explorerLongPressGestureAction:)];
    [self.viewInExplorerButton addGestureRecognizer:recognizer];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

#pragma mark - Public

- (void)setDisplayType:(DWTxDetailDisplayType)displayType {
    _displayType = displayType;

    UIImage *iconImage = nil;
    NSString *title = nil;
    switch (displayType) {
        case DWTxDetailDisplayType_Sent: {
            [self setupIconImageView];

            iconImage = [UIImage imageNamed:@"icon_tx_sent"];
            title = NSLocalizedString(@"Amount Sent", nil);

            break;
        }
        case DWTxDetailDisplayType_Received: {
            [self setupIconImageView];

            iconImage = [UIImage imageNamed:@"icon_tx_received"];
            title = NSLocalizedString(@"Amount Received", nil);

            break;
        }
        case DWTxDetailDisplayType_Moved: {
            [self setupIconImageView];

            iconImage = [UIImage imageNamed:@"icon_tx_received"];
            title = NSLocalizedString(@"Moved to Address", nil);

            break;
        }
        case DWTxDetailDisplayType_Paid: {
            [self setupAnimatedIconView];

            title = NSLocalizedString(@"Paid successfully", nil);

            break;
        }
    }

    if (iconImage) {
        self.iconImageView.image = iconImage;
    }

    self.titleLabel.text = title;
}

- (void)setModel:(nullable DWTxDetailModel *)model {
    _model = model;

    self.fiatAmountLabel.text = model.fiatAmountString;

    [self reloadAttributedData];
}
- (void)viewDidAppear {
    [self.animatedIconView showAnimatedIfNeeded];
}

- (void)setViewInExplorerButtonCopyHintTitle {
    [self.viewInExplorerButton setTitle:NSLocalizedString(@"Long press to copy ID", nil)
                               forState:UIControlStateNormal];
}

#pragma mark - Actions

- (IBAction)viewInExplorerButtonAction:(UIButton *)sender {
    [self.delegate txDetailHeaderView:self viewInExplorerAction:sender];
}

- (void)explorerLongPressGestureAction:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) {
        return;
    }

    BOOL result = [self.model copyTransactionIdToPasteboard];
    if (result) {
        [self dw_showInfoHUDWithText:NSLocalizedString(@"copied", nil)];

        dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(DW_INFO_HUD_DISPLAY_TIME * NSEC_PER_SEC));
        dispatch_after(when, dispatch_get_main_queue(), ^{
            [self setViewInExplorerDefaultTitle];
        });
    }
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
}

- (void)setupIconImageView {
    if (self.iconImageView) {
        return;
    }
    [self.animatedIconView removeFromSuperview];

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.iconContentView addSubview:imageView];
    self.iconImageView = imageView;

    [self pinViewToIconContentView:imageView];
}

- (void)setupAnimatedIconView {
    if (self.animatedIconView) {
        return;
    }
    [self.iconImageView removeFromSuperview];

    DWSuccessfulTransactionAnimatedIconView *animatedIconView =
        [[DWSuccessfulTransactionAnimatedIconView alloc] initWithFrame:CGRectZero];
    animatedIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.iconContentView addSubview:animatedIconView];
    self.animatedIconView = animatedIconView;

    [self pinViewToIconContentView:animatedIconView];
}

- (void)pinViewToIconContentView:(UIView *)view {
    UIView *contentView = self.iconContentView;
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [view.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
    ]];
}

- (void)setViewInExplorerDefaultTitle {
    [self.viewInExplorerButton setTitle:NSLocalizedString(@"View in Explorer", nil)
                               forState:UIControlStateNormal];
}

@end

NS_ASSUME_NONNULL_END
