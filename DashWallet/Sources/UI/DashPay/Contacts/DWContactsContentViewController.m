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

#import "DWContactsContentViewController.h"

#import "DWContactsModel.h"
#import "DWContactsSearchInfoHeaderView.h"
#import "DWDPIncomingRequestItem.h"
#import "DWFilterHeaderView.h"
#import "DWSharedUIConstants.h"
#import "DWTitleActionHeaderView.h"
#import "DWUIKit.h"
#import "UITableView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsContentViewController () <DWFilterHeaderViewDelegate, DWTitleActionHeaderViewDelegate, DWDPIncomingRequestItemDelegate>

@property (null_resettable, nonatomic, strong) DWContactsSearchInfoHeaderView *searchHeaderView;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsContentViewController

- (void)setModel:(DWContactsModel *)model {
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

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    id<DWContactsDataSource> dataSource = self.model.dataSource;
    if ([dataSource tableView:tableView numberOfRowsInSection:section] == 0) {
        return [[UIView alloc] init];
    }

    if (section == 0) {
        const NSUInteger contactRequestsCount = dataSource.contactRequestsCount;
        const BOOL isSearching = self.model.isSearching;
        const BOOL hasMore = contactRequestsCount > dataSource.maxVisibleContactRequestsCount;
        const BOOL shouldHideViewAll = isSearching || !hasMore;
        NSString *title = nil;
        if (shouldHideViewAll) {
            title = NSLocalizedString(@"Contact Requests", nil);
        }
        else {
            title = [NSString stringWithFormat:@"%@ (%ld)",
                                               NSLocalizedString(@"Contact Requests", nil),
                                               contactRequestsCount];
        }

        DWTitleActionHeaderView *headerView = [[DWTitleActionHeaderView alloc] initWithFrame:CGRectZero];
        headerView.titleLabel.text = title;
        headerView.delegate = self;
        headerView.actionButton.hidden = shouldHideViewAll;
        [headerView.actionButton setTitle:NSLocalizedString(@"View All", nil) forState:UIControlStateNormal];
        return headerView;
    }
    else {
        DWFilterHeaderView *headerView = [[DWFilterHeaderView alloc] initWithFrame:CGRectZero];
        headerView.titleLabel.text = NSLocalizedString(@"My Contacts", nil);
        headerView.delegate = self;

        UIButton *button = headerView.filterButton;
        NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
        [result beginEditing];
        NSAttributedString *prefix =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Sort by", nil)
                                            attributes:@{
                                                NSForegroundColorAttributeName : [UIColor dw_tertiaryTextColor],
                                                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1],
                                            }];
        [result appendAttributedString:prefix];

        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
        NSString *optionValue = nil;
        switch (self.model.sortMode) {
            case DWContactsSortMode_ByUsername: {
                optionValue = NSLocalizedString(@"Name", nil);
                break;
            }
        }
        NSAttributedString *option =
            [[NSAttributedString alloc] initWithString:optionValue
                                            attributes:@{
                                                NSForegroundColorAttributeName : [UIColor dw_dashBlueColor],
                                                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote],
                                            }];
        [result appendAttributedString:option];
        [result endEditing];
        [button setAttributedTitle:result forState:UIControlStateNormal];

        return headerView;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    id<DWContactsDataSource> dataSource = self.model.dataSource;
    if ([dataSource tableView:tableView numberOfRowsInSection:section] == 0) {
        return 0.0;
    }

    return UITableViewAutomaticDimension;
}

#pragma mark - DWDPIncomingRequestItemDelegate

- (void)acceptIncomingRequest:(id<DWDPBasicItem>)item {
    [self.model acceptContactRequest:item];
}

- (void)declineIncomingRequest:(id<DWDPBasicItem>)item {
    NSLog(@"DWDP: declineIncomingRequest");
}

#pragma mark - DWFilterHeaderViewDelegate

- (void)filterHeaderView:(DWFilterHeaderView *)view filterButtonAction:(UIView *)sender {
    NSString *title = NSLocalizedString(@"Sort Contacts", nil);
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Name", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        self.model.sortMode = DWContactsSortMode_ByUsername;
                    }];
        [alert addAction:action];
    }

    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:action];
    }

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - DWTitleActionHeaderViewDelegate

- (void)titleActionHeaderView:(DWTitleActionHeaderView *)view buttonAction:(UIView *)sender {
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
