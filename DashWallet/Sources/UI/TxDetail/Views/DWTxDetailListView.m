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

#import "DWTxDetailListView.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const REGULAR_ROW_HEIGHT = 52.0;
static CGFloat const MULTIPLE_ROW_HEIGHT = 40.0;

@interface DWTxDetailListView ()

@property (strong, nonatomic) NSMutableArray<DWTitleDetailCellView *> *inputAddressViews;
@property (strong, nonatomic) NSMutableArray<DWTitleDetailCellView *> *outputAddressViews;
@property (strong, nonatomic) NSMutableArray<DWTitleDetailCellView *> *specialTransactionInfoViews;
@property (nullable, weak, nonatomic) DWTitleDetailCellView *feeCellView;
@property (nullable, weak, nonatomic) DWTitleDetailCellView *dateCellView;

@end

@implementation DWTxDetailListView

@dynamic arrangedSubviews;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self txDetailListView_setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self txDetailListView_setup];
    }
    return self;
}

- (void)setContentPadding:(DWTitleDetailCellViewPadding)contentPadding {
    _contentPadding = contentPadding;

    for (DWTitleDetailCellView *cellView in self.arrangedSubviews) {
        cellView.contentPadding = contentPadding;
    }
}

- (void)configureWithInputAddressesCount:(NSUInteger)inputAddressesCount
                    outputAddressesCount:(NSUInteger)outputAddressesCount
                                  hasFee:(BOOL)hasFee
                                 hasDate:(BOOL)hasDate {
    [self configureWithInputAddressesCount:inputAddressesCount outputAddressesCount:outputAddressesCount specialInfoCount:0 hasFee:hasFee hasDate:hasDate];
}

// Consider using UITableView if reuse is needed
- (void)configureWithInputAddressesCount:(NSUInteger)inputAddressesCount
                    outputAddressesCount:(NSUInteger)outputAddressesCount
                        specialInfoCount:(NSUInteger)specialInfoCount
                                  hasFee:(BOOL)hasFee
                                 hasDate:(BOOL)hasDate {
    const SEL sel = @selector(removeFromSuperview);
    [self.inputAddressViews makeObjectsPerformSelector:sel];
    [self.inputAddressViews removeAllObjects];
    [self.outputAddressViews makeObjectsPerformSelector:sel];
    [self.outputAddressViews removeAllObjects];
    [self.specialTransactionInfoViews makeObjectsPerformSelector:sel];
    [self.specialTransactionInfoViews removeAllObjects];
    [self.feeCellView removeFromSuperview];
    [self.dateCellView removeFromSuperview];


    const CGFloat inputHeight = inputAddressesCount > 1 ? MULTIPLE_ROW_HEIGHT : REGULAR_ROW_HEIGHT;
    for (NSUInteger i = 0; i < inputAddressesCount; i++) {
        DWTitleDetailCellView *cellView = [self addDetailCellViewWithHeight:inputHeight];
        UILongPressGestureRecognizer *recognizer =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(longTapGestureRecognizerAction:)];
        [cellView addGestureRecognizer:recognizer];
        [self.inputAddressViews addObject:cellView];
    }

    const CGFloat outputHeight = outputAddressesCount > 1 ? MULTIPLE_ROW_HEIGHT : REGULAR_ROW_HEIGHT;
    for (NSUInteger i = 0; i < outputAddressesCount; i++) {
        DWTitleDetailCellView *cellView = [self addDetailCellViewWithHeight:outputHeight];
        UILongPressGestureRecognizer *recognizer =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(longTapGestureRecognizerAction:)];
        [cellView addGestureRecognizer:recognizer];
        [self.outputAddressViews addObject:cellView];
    }

    const CGFloat specialInfoHeight = specialInfoCount > 1 ? MULTIPLE_ROW_HEIGHT : REGULAR_ROW_HEIGHT;
    for (NSUInteger i = 0; i < specialInfoCount; i++) {
        DWTitleDetailCellView *cellView = [self addDetailCellViewWithHeight:outputHeight];
        UILongPressGestureRecognizer *recognizer =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(longTapGestureRecognizerAction:)];
        [cellView addGestureRecognizer:recognizer];
        [self.specialTransactionInfoViews addObject:cellView];
    }

    if (hasFee) {
        DWTitleDetailCellView *cellView = [self addDetailCellViewWithHeight:REGULAR_ROW_HEIGHT];
        self.feeCellView = cellView;
    }

    if (hasDate) {
        DWTitleDetailCellView *cellView = [self addDetailCellViewWithHeight:REGULAR_ROW_HEIGHT];
        self.dateCellView = cellView;
    }
}

- (void)updateDataWithInputAddresses:(NSArray<id<DWTitleDetailItem>> *)inputAddresses
                     outputAddresses:(NSArray<id<DWTitleDetailItem>> *)outputAddresses
                                 fee:(nullable id<DWTitleDetailItem>)fee
                                date:(nullable id<DWTitleDetailItem>)date {
    [self updateDataWithInputAddresses:inputAddresses outputAddresses:outputAddresses specialInfo:[NSArray array] fee:fee date:date];
}

- (void)updateDataWithInputAddresses:(NSArray<id<DWTitleDetailItem>> *)inputAddresses
                     outputAddresses:(NSArray<id<DWTitleDetailItem>> *)outputAddresses
                         specialInfo:(NSArray<id<DWTitleDetailItem>> *)specialInfo
                                 fee:(nullable id<DWTitleDetailItem>)fee
                                date:(nullable id<DWTitleDetailItem>)date {
    NSAssert(self.inputAddressViews.count == inputAddresses.count, @"DWTxDetailListView is not configured");
    NSAssert(self.outputAddressViews.count == outputAddresses.count, @"DWTxDetailListView is not configured");
    NSAssert(self.specialTransactionInfoViews.count == specialInfo.count, @"DWTxDetailListView is not configured");

    for (NSUInteger i = 0; i < inputAddresses.count; i++) {
        id<DWTitleDetailItem> item = inputAddresses[i];
        DWTitleDetailCellView *cellView = self.inputAddressViews[i];
        cellView.model = item;
        const BOOL separatorHidden = i != (inputAddresses.count - 1);
        cellView.separatorPosition = (separatorHidden
                                          ? DWTitleDetailCellViewSeparatorPosition_Hidden
                                          : DWTitleDetailCellViewSeparatorPosition_Bottom);
    }

    for (NSUInteger i = 0; i < outputAddresses.count; i++) {
        id<DWTitleDetailItem> item = outputAddresses[i];
        DWTitleDetailCellView *cellView = self.outputAddressViews[i];
        cellView.model = item;
        const BOOL separatorHidden = i != (outputAddresses.count - 1);
        cellView.separatorPosition = (separatorHidden
                                          ? DWTitleDetailCellViewSeparatorPosition_Hidden
                                          : DWTitleDetailCellViewSeparatorPosition_Bottom);
    }

    for (NSUInteger i = 0; i < specialInfo.count; i++) {
        id<DWTitleDetailItem> item = specialInfo[i];
        DWTitleDetailCellView *cellView = self.specialTransactionInfoViews[i];
        cellView.model = item;
        const BOOL separatorHidden = i != (specialInfo.count - 1);
        cellView.separatorPosition = (separatorHidden
                                          ? DWTitleDetailCellViewSeparatorPosition_Hidden
                                          : DWTitleDetailCellViewSeparatorPosition_Bottom);
    }

    self.feeCellView.model = fee;
    self.dateCellView.model = date;
}

#pragma mark - Actions

- (void)longTapGestureRecognizerAction:(UIGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) {
        return;
    }

    DWTitleDetailCellView *view = (DWTitleDetailCellView *)sender.view;
    if (![view isKindOfClass:DWTitleDetailCellView.class]) {
        return;
    }

    [self.delegate txDetailListView:self longPressActionOnView:view];
}

#pragma mark - Private

- (void)txDetailListView_setup {
    self.axis = UILayoutConstraintAxisVertical;
    self.distribution = UIStackViewDistributionFill;
    self.alignment = UIStackViewAlignmentFill;
    self.spacing = 0;

    self.inputAddressViews = [NSMutableArray array];
    self.outputAddressViews = [NSMutableArray array];
    self.specialTransactionInfoViews = [NSMutableArray array];
}

- (DWTitleDetailCellView *)addDetailCellViewWithHeight:(CGFloat)height {
    DWTitleDetailCellView *cellView = [[DWTitleDetailCellView alloc] initWithFrame:CGRectZero];
    cellView.translatesAutoresizingMaskIntoConstraints = NO;
    cellView.contentPadding = self.contentPadding;
    [self addArrangedSubview:cellView];

    [cellView.heightAnchor constraintEqualToConstant:height].active = YES;

    return cellView;
}

@end

NS_ASSUME_NONNULL_END
