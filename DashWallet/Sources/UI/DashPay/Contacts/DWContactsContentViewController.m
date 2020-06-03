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

#import "DWBaseContactsModel.h"
#import "DWFilterHeaderView.h"
#import "DWTitleActionHeaderView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsContentViewController () <DWTitleActionHeaderViewDelegate, DWFilterHeaderViewDelegate>

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsContentViewController

#pragma mark - UITableViewDelegate

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

@end
