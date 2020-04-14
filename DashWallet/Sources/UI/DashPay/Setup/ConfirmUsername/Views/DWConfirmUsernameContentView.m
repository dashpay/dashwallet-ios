//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWConfirmUsernameContentView.h"

#import "DWCheckbox.h"
#import "DWDashPayConstants.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWBuilder.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

static CGSize const DashSymbolMainSize = {35.0, 27.0};

@interface DWConfirmUsernameContentView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *mainAmountLabel;
@property (weak, nonatomic) IBOutlet UILabel *supplementaryAmountLabel;
@property (weak, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (weak, nonatomic) IBOutlet DWCheckbox *confirmationCheckbox;

@end

NS_ASSUME_NONNULL_END

@implementation DWConfirmUsernameContentView

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

    self.titleLabel.text = NSLocalizedString(@"Upgrade Fee", nil);

    // These two labels doesn't support Dynamic Type and have same hardcoded values as in DWAmountInputControl
    self.mainAmountLabel.font = [UIFont dw_regularFontOfSize:34.0];
    self.supplementaryAmountLabel.font = [UIFont dw_regularFontOfSize:16.0];

    const uint64_t amount = DWDP_MIN_BALANCE_TO_CREATE_USERNAME;
    self.mainAmountLabel.attributedText = [self mainAmountAttributedStringForAmount:amount];
    self.supplementaryAmountLabel.text = [self supplementaryAmountStringForAmount:amount];

    self.confirmationCheckbox.title = NSLocalizedString(@"I Accept", nil);
    self.confirmationCheckbox.backgroundColor = self.backgroundColor;

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)setUsername:(NSString *)username {
    _username = username;

    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    if (self.username.length == 0) {
        self.descriptionLabel.attributedText = nil;
        return;
    }

    UIColor *color = [UIColor dw_secondaryTextColor];
    NSString *format = NSLocalizedString(@"You have chosen \"%@\" as your username. Username cannot be changed once it's registered", nil);
    NSString *text = [NSString stringWithFormat:format, self.username];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote],
        NSForegroundColorAttributeName : color,
    };

    NSRange usernameRange = [text rangeOfString:self.username];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
    [result beginEditing];
    [result removeAttribute:NSFontAttributeName range:usernameRange];
    [result addAttribute:NSFontAttributeName value:[UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline] range:usernameRange];
    [result endEditing];

    self.descriptionLabel.attributedText = result;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
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
