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

#import "DWBlueActionButton.h"
#import "DWTitleDetailCellView.h"
#import "DWTxDetailHeaderView.h"
#import "DWTxDetailListView.h"
#import "DWTxDetailModel.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const CLOSE_BUTTON_HEIGHT = 39.0;
static CGFloat const CLOSE_BUTTON_DETAILS_PADDING = 30.0;

@interface DWTxDetailContentView () <DWTxDetailHeaderViewDelegate, DWTxDetailListViewDelegate>

@property (readonly, strong, nonatomic) UIView *headerContentView;
@property (readonly, strong, nonatomic) DWTxDetailHeaderView *headerView;
@property (readonly, strong, nonatomic) UIScrollView *detailsScrollView;
@property (readonly, strong, nonatomic) DWTxDetailListView *detailListView;
@property (readonly, strong, nonatomic) UIButton *closeButton;

@end

@implementation DWTxDetailContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIView *headerContentView = [[UIView alloc] initWithFrame:CGRectZero];
        headerContentView.backgroundColor = self.backgroundColor;
        [self addSubview:headerContentView];
        _headerContentView = headerContentView;

        DWTxDetailHeaderView *headerView = [[DWTxDetailHeaderView alloc] initWithFrame:CGRectZero];
        headerView.translatesAutoresizingMaskIntoConstraints = NO;
        headerView.delegate = self;
        [headerContentView addSubview:headerView];
        _headerView = headerView;

        UIScrollView *detailsScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        detailsScrollView.backgroundColor = self.backgroundColor;
        [self addSubview:detailsScrollView];
        _detailsScrollView = detailsScrollView;

        DWTxDetailListView *detailListView = [[DWTxDetailListView alloc] initWithFrame:CGRectZero];
        detailListView.translatesAutoresizingMaskIntoConstraints = NO;
        detailListView.delegate = self;
        [detailsScrollView addSubview:detailListView];
        _detailListView = detailListView;

        DWBlueActionButton *closeButton = [[DWBlueActionButton alloc] initWithFrame:CGRectZero];
        closeButton.usedOnDarkBackground = NO;
        closeButton.small = YES;
        [closeButton setTitle:NSLocalizedString(@"Close", nil) forState:UIControlStateNormal];
        [closeButton addTarget:self
                        action:@selector(closeButtonAction:)
              forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeButton];
        _closeButton = closeButton;

        [NSLayoutConstraint activateConstraints:@[
            [headerView.topAnchor constraintEqualToAnchor:headerContentView.topAnchor],
            [headerView.leadingAnchor constraintEqualToAnchor:headerContentView.leadingAnchor],
            [headerView.bottomAnchor constraintEqualToAnchor:headerContentView.bottomAnchor],
            [headerView.trailingAnchor constraintEqualToAnchor:headerContentView.trailingAnchor],

            [detailListView.topAnchor constraintEqualToAnchor:detailsScrollView.topAnchor],
            [detailListView.leadingAnchor constraintEqualToAnchor:detailsScrollView.leadingAnchor],
            [detailListView.bottomAnchor constraintEqualToAnchor:detailsScrollView.bottomAnchor],
            [detailListView.trailingAnchor constraintEqualToAnchor:detailsScrollView.trailingAnchor],
            [detailListView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
        ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(contentSizeCategoryDidChangeNotification)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;

    const CGFloat headerHeight =
        [self.headerView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    const CGFloat detailsHeight =
        [self.detailListView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;

    CGFloat contentHeight = headerHeight + CLOSE_BUTTON_DETAILS_PADDING + CLOSE_BUTTON_HEIGHT;
    CGFloat scrollViewHeight;
    if (contentHeight + detailsHeight <= size.height) {
        contentHeight += detailsHeight;
        scrollViewHeight = detailsHeight;
    }
    else {
        scrollViewHeight = size.height - headerHeight - CLOSE_BUTTON_DETAILS_PADDING - CLOSE_BUTTON_HEIGHT;
        contentHeight += scrollViewHeight;
    }

    CGFloat y = (size.height - contentHeight) / 2.0;
    self.headerContentView.frame = CGRectMake(0.0, y, size.width, headerHeight);
    y += headerHeight;

    self.detailsScrollView.frame = CGRectMake(0.0, y, size.width, scrollViewHeight);
    y += scrollViewHeight + CLOSE_BUTTON_DETAILS_PADDING;

    const CGFloat buttonWidth = [self.closeButton sizeThatFits:CGSizeZero].width;
    self.closeButton.frame = CGRectMake((size.width - buttonWidth) / 2.0,
                                        y,
                                        buttonWidth,
                                        CLOSE_BUTTON_HEIGHT);
}

- (void)setDisplayType:(DWTxDetailDisplayType)displayType {
    _displayType = displayType;

    self.headerView.displayType = displayType;

    const DWTitleDetailCellViewPadding contentPadding = displayType == DWTxDetailDisplayType_Paid
                                                            ? DWTitleDetailCellViewPadding_None
                                                            : DWTitleDetailCellViewPadding_Small;
    self.detailListView.contentPadding = contentPadding;
}

- (void)setModel:(nullable DWTxDetailModel *)model {
    _model = model;

    self.headerView.model = model;

    [self.detailListView configureWithInputAddressesCount:[model inputAddressesCount]
                                     outputAddressesCount:[model outputAddressesCount]
                                                   hasFee:[model hasFee]
                                                  hasDate:[model hasDate]];

    [self reloadAttributedData];
}

- (void)viewDidAppear {
    [self.headerView viewDidAppear];
}

- (void)setViewInExplorerButtonCopyHintTitle {
    [self.headerView setViewInExplorerButtonCopyHintTitle];
}

#pragma mark - Actions

- (void)closeButtonAction:(UIButton *)sender {
    [self.delegate txDetailContentView:self closeButtonAction:sender];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
    [self setNeedsLayout];
}

#pragma mark - DWTxDetailHeaderViewDelegate

- (void)txDetailHeaderView:(DWTxDetailHeaderView *)view viewInExplorerAction:(UIButton *)sender {
    [self.delegate txDetailContentView:self viewInExplorerButtonAction:sender];
}

#pragma mark - DWTxDetailListViewDelegate

- (void)txDetailListView:(DWTxDetailListView *)view longPressActionOnView:(DWTitleDetailCellView *)cellView {
    NSString *copyableData = cellView.model.copyableData;
    if (!copyableData) {
        return;
    }

    [UIPasteboard generalPasteboard].string = copyableData;

    [self dw_showInfoHUDWithText:NSLocalizedString(@"copied", nil)];
}

#pragma mark - Private

- (void)reloadAttributedData {
    DWTxDetailModel *model = self.model;

    UIFont *detailFont = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    NSArray<id<DWTitleDetailItem>> *inputAddresses = [model inputAddressesWithFont:detailFont];
    NSArray<id<DWTitleDetailItem>> *outputAddresses = [model outputAddressesWithFont:detailFont];
    id<DWTitleDetailItem> fee = [model feeWithFont:detailFont tintColor:[UIColor dw_secondaryTextColor]];
    id<DWTitleDetailItem> date = [model date];
    [self.detailListView updateDataWithInputAddresses:inputAddresses
                                      outputAddresses:outputAddresses
                                                  fee:fee
                                                 date:date];
}

@end

NS_ASSUME_NONNULL_END
