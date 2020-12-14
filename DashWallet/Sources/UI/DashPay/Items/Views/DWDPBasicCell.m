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

#import "DWDPBasicCell.h"

#import "DWShadowView.h"
#import "DWUIKit.h"
#import "NSAttributedString+DWHighlightText.h"
#import "UIFont+DWDPItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPBasicCell ()

@property (readonly, nonatomic, strong) DWShadowView *shadowView;
@property (readonly, nonatomic, strong) UIView *roundedContentView;
@property (nullable, nonatomic, copy) NSString *highlightedText;
@property (nullable, nonatomic, strong) NSLayoutConstraint *contentWidthConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPBasicCell

+ (Class)itemViewClass {
    return DWDPGenericItemView.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:shadowView];
        _shadowView = shadowView;

        UIView *roundedContentView = [[UIView alloc] initWithFrame:CGRectZero];
        roundedContentView.translatesAutoresizingMaskIntoConstraints = NO;
        roundedContentView.backgroundColor = [UIColor dw_backgroundColor];
        roundedContentView.layer.cornerRadius = 8.0;
        roundedContentView.layer.masksToBounds = YES;
        _roundedContentView = roundedContentView;
        [shadowView addSubview:roundedContentView];

        Class klass = [self.class itemViewClass];
        DWDPGenericItemView *itemView = [[klass alloc] initWithFrame:CGRectZero];
        itemView.translatesAutoresizingMaskIntoConstraints = NO;
        itemView.backgroundColor = self.backgroundColor;
        [self.contentView addSubview:itemView];
        _itemView = itemView;

        const CGFloat horizontalPadding = 10.0;
        const CGFloat verticalPadding = 10.0;
        const CGFloat itemVerticalPadding = 23.0;
        const CGFloat itemHorizontalPadding = verticalPadding + 10.0;

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [shadowView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                 constant:verticalPadding],
            [shadowView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                     constant:horizontalPadding],
            [guide.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor
                                                 constant:horizontalPadding],
            [self.contentView.bottomAnchor constraintEqualToAnchor:shadowView.bottomAnchor
                                                          constant:verticalPadding],

            [roundedContentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [roundedContentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [shadowView.trailingAnchor constraintEqualToAnchor:roundedContentView.trailingAnchor],
            [shadowView.bottomAnchor constraintEqualToAnchor:roundedContentView.bottomAnchor],

            [itemView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                               constant:itemVerticalPadding],
            [itemView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                   constant:itemHorizontalPadding],
            [guide.trailingAnchor constraintEqualToAnchor:itemView.trailingAnchor
                                                 constant:itemHorizontalPadding],
            [self.contentView.bottomAnchor constraintEqualToAnchor:itemView.bottomAnchor
                                                          constant:itemVerticalPadding],
            (_contentWidthConstraint = [self.contentView.widthAnchor constraintEqualToConstant:200]),
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];
    }
    return self;
}

- (void)setBackgroundStyle:(DWDPBasicCellBackgroundStyle)backgroundStyle {
    _backgroundStyle = backgroundStyle;

    switch (backgroundStyle) {
        case DWDPBasicCellBackgroundStyle_GrayOnGray:
            self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
            self.itemView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
            self.shadowView.hidden = YES;
            break;
        case DWDPBasicCellBackgroundStyle_WhiteOnGray:
            self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
            self.itemView.backgroundColor = [UIColor dw_backgroundColor];
            self.roundedContentView.backgroundColor = [UIColor dw_backgroundColor];
            self.shadowView.hidden = NO;
            break;
        case DWDPBasicCellBackgroundStyle_GrayOnWhite:
            self.backgroundColor = [UIColor dw_backgroundColor];
            self.itemView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
            self.roundedContentView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
            self.shadowView.hidden = NO;
            break;
    }
    self.contentView.backgroundColor = self.backgroundColor;
}

- (CGFloat)contentWidth {
    return self.contentWidthConstraint.constant;
}

- (void)setContentWidth:(CGFloat)contentWidth {
    self.contentWidthConstraint.constant = contentWidth;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)setItem:(id<DWDPBasicItem>)item {
    [self setItem:item highlightedText:nil];
}

- (void)setItem:(id<DWDPBasicItem>)item highlightedText:(NSString *)highlightedText {
    NSString *key = DW_KEYPATH(self, item);
    [self willChangeValueForKey:key];
    _item = item;
    [self didChangeValueForKey:key];

    self.highlightedText = highlightedText;

    self.itemView.avatarView.blockchainIdentity = item.blockchainIdentity;

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    UIColor *highlightedTextColor = [UIColor dw_dashBlueColor];

    NSAttributedString *titleString = [NSAttributedString
              attributedText:self.item.title
                   textColor:[UIColor dw_darkTitleColor]
             highlightedText:self.highlightedText
        highlightedTextColor:highlightedTextColor];

    NSAttributedString *subtitleString = [NSAttributedString
              attributedText:self.item.subtitle
                        font:[UIFont dw_itemSubtitleFont]
                   textColor:[UIColor dw_tertiaryTextColor]
             highlightedText:self.highlightedText
        highlightedTextColor:highlightedTextColor];

    NSAttributedString *resultString = nil;
    if (titleString && subtitleString) {
        NSMutableAttributedString *mutableResultString = [[NSMutableAttributedString alloc] init];
        [mutableResultString beginEditing];

        [mutableResultString appendAttributedString:titleString];

        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.maximumLineHeight = 4.0;
        NSAttributedString *spacingString = [[NSAttributedString alloc] initWithString:@"\n\n"
                                                                            attributes:@{NSParagraphStyleAttributeName : style}];
        [mutableResultString appendAttributedString:spacingString];

        [mutableResultString appendAttributedString:subtitleString];

        [mutableResultString endEditing];
        resultString = [mutableResultString copy];
    }
    else {
        resultString = titleString;
    }

    self.itemView.textLabel.attributedText = resultString;
}

@end
