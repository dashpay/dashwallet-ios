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

#import "DWNoNotificationsCell.h"
#import "DWNotificationsModel.h"
#import "DWTitleActionHeaderView.h"
#import "DWUIKit.h"
#import "DWUserDetailsCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsViewController () <DWUserDetailsCellDelegate>

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

- (void)viewDidLoad {
    [super viewDidLoad];

    [self updateTitle];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    [self.tableView registerClass:DWNoNotificationsCell.class
           forCellReuseIdentifier:DWNoNotificationsCell.dw_reuseIdentifier];

    [self.model.dataSource setupWithTableView:self.tableView userDetailsDelegate:self];
    self.tableView.dataSource = self.model.dataSource;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWNoNotificationsCell *cell = [tableView dequeueReusableCellWithIdentifier:DWNoNotificationsCell.dw_reuseIdentifier
                                                                  forIndexPath:indexPath];
    return cell;
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
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

#pragma mark - DWUserDetailsCellDelegate

- (void)userDetailsCell:(DWUserDetailsCell *)cell didAcceptContact:(id<DWUserDetails>)contact {
    //    [self.model acceptContactRequest:contact];
}

- (void)userDetailsCell:(DWUserDetailsCell *)cell didDeclineContact:(id<DWUserDetails>)contact {
    NSLog(@"DWDP: ignore contact request");
}

#pragma mark - Private

- (DWNotificationsModel *)model {
    if (!_model) {
        _model = [[DWNotificationsModel alloc] init];
    }
    return _model;
}

- (void)updateTitle {
    self.title = NSLocalizedString(@"Notifications", nil);
}

@end
