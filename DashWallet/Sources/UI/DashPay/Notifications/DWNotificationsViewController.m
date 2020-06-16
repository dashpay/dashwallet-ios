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

#import "DWNotificationsViewController.h"

#import "DWDPBasicCell.h"
#import "DWDPIncomingRequestItem.h"
#import "DWNoNotificationsCell.h"
#import "DWNotificationsModel.h"
#import "DWTitleActionHeaderView.h"
#import "DWUIKit.h"
#import "UITableView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsViewController () <DWNotificationsModelDelegate, DWDPIncomingRequestItemDelegate>

@property (null_resettable, nonatomic, strong) DWNotificationsModel *model;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self updateTitle];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.tableView dw_registerDPItemCells];
    [self.tableView registerClass:DWNoNotificationsCell.class
           forCellReuseIdentifier:DWNoNotificationsCell.dw_reuseIdentifier];

    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.model markNotificationsAsViewed];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.isMovingFromParentViewController) {
        [self.model processUnreadNotifications];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DWNotificationsData *data = self.model.data;
    if (section == 0) {
        if (data.unreadItems.count == 0) {
            return 1; // empty state
        }
        else {
            return data.unreadItems.count;
        }
    }
    else {
        return data.oldItems.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && self.model.data.unreadItems.count == 0) {
        DWNoNotificationsCell *cell = [tableView dequeueReusableCellWithIdentifier:DWNoNotificationsCell.dw_reuseIdentifier
                                                                      forIndexPath:indexPath];
        return cell;
    }

    id<DWDPBasicItem> item = [self itemAtIndexPath:indexPath];

    DWDPBasicCell *cell = [tableView dw_dequeueReusableCellForItem:item atIndexPath:indexPath];
    cell.displayItemBackgroundView = indexPath.section == 0;
    cell.delegate = self;
    cell.item = item;
    return cell;
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    // hide Earlier section header if it's empty
    if (section == 1 && [tableView numberOfRowsInSection:section] == 0) {
        return [[UIView alloc] init];
    }

    NSString *title = nil;
    if (section == 0) {
        title = NSLocalizedString(@"New", @"(List of) New (notifications)");
    }
    else {
        title = NSLocalizedString(@"Earlier", @"(List of notifications happened) Earlier (some time ago)");
    }

    DWTitleActionHeaderView *view = [[DWTitleActionHeaderView alloc] initWithFrame:CGRectZero];
    view.titleLabel.text = title;
    view.actionButton.hidden = YES;
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // hide Earlier section header if it's empty
    if (section == 1 && [tableView numberOfRowsInSection:section] == 0) {
        return 0.0;
    }

    return UITableViewAutomaticDimension;
}

#pragma mark - DWNotificationsModelDelegate

- (void)notificationsModelDidUpdate:(DWNotificationsModel *)model {
    [self.tableView reloadData];
    [self updateTitle];
}

#pragma mark - DWDPIncomingRequestItemDelegate

- (void)acceptIncomingRequest:(id<DWDPBasicItem>)item {
    [self.model acceptContactRequest:item];
}

- (void)declineIncomingRequest:(id<DWDPBasicItem>)item {
    NSLog(@"DWDP: declineIncomingRequest");
}

#pragma mark - Private

- (DWNotificationsModel *)model {
    if (!_model) {
        _model = [[DWNotificationsModel alloc] init];
        _model.delegate = self;
    }
    return _model;
}

- (void)updateTitle {
    const NSUInteger unreadCount = self.model.data.unreadItems.count;
    NSString *title = NSLocalizedString(@"Notifications", nil);
    if (unreadCount > 0) {
        self.title = [NSString stringWithFormat:@"%@ (%ld)", title, unreadCount];
    }
    else {
        self.title = title;
    }
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    DWNotificationsData *data = self.model.data;
    NSArray<id<DWDPBasicItem>> *items = indexPath.section == 0 ? data.unreadItems : data.oldItems;
    return items[indexPath.row];
}

@end
