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

#import "DWTxListHomeCell.h"

#import "DSBlockchainIdentity+DWDisplayName.h"
#import "DWDPTxItemView.h"
#import "DWDPUserObject.h"
#import "DWEnvironment.h"
#import "DWUIKit.h"
#import "UIFont+DWDPItem.h"

#import <DashSync/DSTransaction.h>

NS_ASSUME_NONNULL_BEGIN

static NSAttributedString *AttributedString(NSString *string, UIFont *font, UIColor *textColor) {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : textColor,
    };
    return [[NSAttributedString alloc] initWithString:string attributes:attributes];
}

static NSAttributedString *DirectionStateString(id<DWTransactionListDataItem> transactionData, NSString *dashpayUsername) {
    UIFont *directionFont = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    UIColor *directionColor = [UIColor dw_darkTitleColor];


    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];

    [attributedString appendAttributedString:AttributedString(dashpayUsername ?: transactionData.directionText,
                                                              directionFont,
                                                              directionColor)];

    if (transactionData.stateText) {
        [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];

        UIFont *stateFont = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        [attributedString appendAttributedString:AttributedString(transactionData.stateText,
                                                                  stateFont,
                                                                  transactionData.stateTintColor)];
    }

    return [attributedString copy];
}

@interface DWTxListHomeCell ()

@property (readonly, nonatomic, strong) DWDPTxItemView *itemView;

@property (nullable, nonatomic, weak) id<DWTransactionListDataProviderProtocol> dataProvider;
@property (nonatomic, strong) DSTransaction *transaction;
@property (nonatomic, strong) id<DWTransactionListDataItem> transactionData;
@property (nullable, copy, nonatomic) NSString *dashpayUsername;
@property (nullable, nonatomic, strong) id<DWDPBasicUserItem> userItem;

@end

NS_ASSUME_NONNULL_END

@implementation DWTxListHomeCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        DWDPTxItemView *itemView = [[DWDPTxItemView alloc] initWithFrame:CGRectZero];
        itemView.translatesAutoresizingMaskIntoConstraints = NO;
        itemView.backgroundColor = self.backgroundColor;
        [self.contentView addSubview:itemView];
        _itemView = itemView;

        const CGFloat verticalPadding = 5.0;
        const CGFloat itemVerticalPadding = 18.0;
        const CGFloat itemHorizontalPadding = verticalPadding + 10.0;
        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [itemView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                               constant:itemVerticalPadding],
            [itemView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                   constant:itemHorizontalPadding],
            [guide.trailingAnchor constraintEqualToAnchor:itemView.trailingAnchor
                                                 constant:itemHorizontalPadding],
            [self.contentView.bottomAnchor constraintEqualToAnchor:itemView.bottomAnchor
                                                          constant:itemVerticalPadding],
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];

        UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapRecognizerAction:)];
        [itemView.avatarView addGestureRecognizer:tapRecognizer];
    }
    return self;
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self.contentView dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)configureWithTransaction:(DSTransaction *)transaction
                    dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    NSParameterAssert(dataProvider);

    self.dataProvider = dataProvider;
    self.transaction = transaction;
    self.transactionData = [self.dataProvider transactionDataForTransaction:transaction];

    DSBlockchainIdentity *source = [transaction.sourceBlockchainIdentities anyObject];
    DSBlockchainIdentity *destination = [transaction.destinationBlockchainIdentities anyObject];
    DSBlockchainIdentity *currentUser = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    if (currentUser == nil) {
        [self.itemView.avatarView setAsDashPlaceholder];
        self.dashpayUsername = nil;
        self.userItem = nil;
    }
    else {
        if (source != nil && !uint256_eq(source.uniqueID, currentUser.uniqueID)) {
            self.itemView.avatarView.username = source.currentDashpayUsername;
            self.dashpayUsername = source.dw_displayNameOrUsername;
            self.userItem = [[DWDPUserObject alloc] initWithBlockchainIdentity:source];
        }
        else if (destination != nil && !uint256_eq(destination.uniqueID, currentUser.uniqueID)) {
            self.itemView.avatarView.username = destination.currentDashpayUsername;
            self.dashpayUsername = destination.dw_displayNameOrUsername;
            self.userItem = [[DWDPUserObject alloc] initWithBlockchainIdentity:destination];
        }
        else {
            [self.itemView.avatarView setAsDashPlaceholder];
            self.dashpayUsername = nil;
            self.userItem = nil;
        }
    }

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)tapRecognizerAction:(UIGestureRecognizer *)sender {
    if (self.userItem == nil) {
        return;
    }
    [self.delegate openUserProfile:self.userItem];
}

- (void)reloadAttributedData {
    UIFont *titleFont = [UIFont dw_itemTitleFont];
    UIFont *subtitleFont = [UIFont dw_itemSubtitleFont];
    UIColor *subtitleColor = [UIColor dw_tertiaryTextColor];

    // Left side label

    NSAttributedString *titleString = DirectionStateString(self.transactionData, self.dashpayUsername);
    NSAttributedString *subtitleString = AttributedString([self.dataProvider shortDateStringForTransaction:self.transaction],
                                                          subtitleFont,
                                                          subtitleColor);

    NSAttributedString *resultString = nil;
    if (titleString && subtitleString) {
        NSMutableAttributedString *mutableResultString = [[NSMutableAttributedString alloc] init];
        [mutableResultString beginEditing];
        [mutableResultString appendAttributedString:titleString];
        [mutableResultString appendAttributedString:[self spacingString]];
        [mutableResultString appendAttributedString:subtitleString];
        [mutableResultString endEditing];
        resultString = [mutableResultString copy];
    }
    else {
        resultString = titleString;
    }

    self.itemView.textLabel.attributedText = resultString;

    // Right side label

    NSAttributedString *dashAmountString = [self.dataProvider dashAmountStringFrom:self.transactionData font:titleFont];
    NSAttributedString *fiatString = AttributedString(self.transactionData.fiatAmount, subtitleFont, subtitleColor);

    NSMutableAttributedString *amountString = [[NSMutableAttributedString alloc] init];
    [amountString beginEditing];
    [amountString appendAttributedString:dashAmountString];
    [amountString appendAttributedString:[self spacingString]];
    [amountString appendAttributedString:fiatString];
    [amountString endEditing];

    self.itemView.amountLabel.attributedText = amountString;
}

- (NSAttributedString *)spacingString {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.maximumLineHeight = 4.0;
    NSAttributedString *spacingString = [[NSAttributedString alloc] initWithString:@"\n\n"
                                                                        attributes:@{NSParagraphStyleAttributeName : style}];
    return spacingString;
}

@end
