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

#import "DWBaseContactsContentViewController.h"

#import "DWBaseContactsModel.h"
#import "DWContactsSearchInfoHeaderView.h"
#import "DWDPNewIncomingRequestItem.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "UITableView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseContactsContentViewController () <DWDPNewIncomingRequestItemDelegate>

@property (null_resettable, nonatomic, strong) DWContactsSearchInfoHeaderView *searchHeaderView;

@end

NS_ASSUME_NONNULL_END

@implementation DWBaseContactsContentViewController

- (void)setModel:(DWBaseContactsModel *)model {
    _model = model;
    [model.dataSource setupWithTableView:self.tableView itemsDelegate:self];
    self.tableView.dataSource = model.dataSource;
}

- (void)updateSearchingState {
    NSString *query = self.model.dataSource.trimmedQuery;
    if (query.length == 0) {
        self.tableView.tableHeaderView = nil;
    }
    else {
        NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
        [result beginEditing];
        NSDictionary<NSAttributedStringKey, id> *plainAttributes = @{
            NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote],
        };
        NSAttributedString *prefix =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Search results for \"", @"Search results for \"John Doe\"")
                                            attributes:plainAttributes];
        [result appendAttributedString:prefix];
        NSAttributedString *queryString =
            [[NSAttributedString alloc] initWithString:query
                                            attributes:@{
                                                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline],
                                            }];
        [result appendAttributedString:queryString];
        NSAttributedString *suffix = [[NSAttributedString alloc] initWithString:@"\"" attributes:plainAttributes];
        [result appendAttributedString:suffix];
        [result endEditing];

        self.searchHeaderView.titleLabel.attributedText = result;

        // For very first search header apperance we have to do layout cycle twice.
        if (self.tableView.tableHeaderView == nil) {
            self.tableView.tableHeaderView = self.searchHeaderView;
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        }

        self.tableView.tableHeaderView = self.searchHeaderView;
        [self.view setNeedsLayout];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.tableView dw_registerDPItemCells];
    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, DW_TABBAR_NOTCH, 0.0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UIView *tableHeaderView = self.tableView.tableHeaderView;
    if (tableHeaderView) {
        CGSize fittingSize = CGSizeMake(CGRectGetWidth(self.tableView.bounds), UILayoutFittingCompressedSize.height);
        CGSize headerSize = [tableHeaderView systemLayoutSizeFittingSize:fittingSize];
        if (CGRectGetHeight(tableHeaderView.frame) != headerSize.height) {
            tableHeaderView.frame = CGRectMake(0.0, 0.0, headerSize.width, headerSize.height);
            self.tableView.tableHeaderView = nil;
            self.tableView.tableHeaderView = tableHeaderView;
        }
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    id<DWDPBasicItem> item = [self.model.dataSource itemAtIndexPath:indexPath];
    [self.delegate contactsContentViewController:self didSelectItem:item];
}

#pragma mark - DWDPIncomingRequestItemDelegate

- (void)acceptIncomingRequest:(id<DWDPBasicItem>)item {
    [self.model acceptContactRequest:item];
}

- (void)declineIncomingRequest:(id<DWDPBasicItem>)item {
    [self.model declineContactRequest:item];
}

#pragma mark - Private

- (DWContactsSearchInfoHeaderView *)searchHeaderView {
    if (_searchHeaderView == nil) {
        _searchHeaderView = [[DWContactsSearchInfoHeaderView alloc] initWithFrame:CGRectZero];
        _searchHeaderView.preservesSuperviewLayoutMargins = YES;
    }
    return _searchHeaderView;
}

@end
