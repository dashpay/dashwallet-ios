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

#import "DWMainMenuContentView.h"

#import "DWDPWelcomeMenuView.h"
#import "DWDashPayReadyProtocol.h"
#import "DWMainMenuModel.h"
#import "DWMainMenuTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "DWUserProfileContainerView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuContentView () <UITableViewDataSource, UITableViewDelegate, DWCurrentUserProfileViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) DWUserProfileContainerView *headerView;
@property (nonatomic, strong) DWDPWelcomeMenuView *joinHeaderView;

@end

@implementation DWMainMenuContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UITableView *tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tableView.backgroundColor = self.backgroundColor;
        tableView.dataSource = self;
        tableView.delegate = self;
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 74.0;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, DW_TABBAR_NOTCH, 0.0);
        [self addSubview:tableView];
        _tableView = tableView;

        DWUserProfileContainerView *headerView = [[DWUserProfileContainerView alloc] initWithFrame:CGRectZero];
        headerView.delegate = self;
        _headerView = headerView;

        DWDPWelcomeMenuView *joinHeaderView = [[DWDPWelcomeMenuView alloc] initWithFrame:CGRectZero];
        [joinHeaderView.joinButton addTarget:self
                                      action:@selector(joinButtonAction:)
                            forControlEvents:UIControlEventTouchUpInside];
        _joinHeaderView = joinHeaderView;

        NSString *cellId = DWMainMenuTableViewCell.dw_reuseIdentifier;
        UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
        NSParameterAssert(nib);
        [tableView registerNib:nib forCellReuseIdentifier:cellId];

        [self mvvm_observe:DW_KEYPATH(self, userModel.state)
                      with:^(typeof(self) self, id value) {
                          [self updateHeader];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, dashPayReady.isDashPayReady)
                      with:^(typeof(self) self, id value) {
                          [self updateHeader];
                      }];
    }
    return self;
}

- (void)setModel:(DWMainMenuModel *)model {
    _model = model;

    [self.tableView reloadData];
}

- (void)setUserModel:(DWCurrentUserProfileModel *)userModel {
    _userModel = userModel;

    self.headerView.userModel = userModel;
}

- (void)updateUserHeader {
    [self.userModel update];
    [self updateHeader];
}

- (void)updateHeader {
    UIView *header = nil;
    if (self.dashPayReady.isDashPayReady) {
        header = self.joinHeaderView;
    }
    else if (self.userModel.blockchainIdentity != nil) {
        [self.headerView update];
        header = self.headerView;
    }

    self.tableView.tableHeaderView = header;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    UIView *tableHeaderView = self.tableView.tableHeaderView;
    if (tableHeaderView) {
        CGSize headerSize = [tableHeaderView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (CGRectGetHeight(tableHeaderView.frame) != headerSize.height) {
            tableHeaderView.frame = CGRectMake(0.0, 0.0, headerSize.width, headerSize.height);
            self.tableView.tableHeaderView = tableHeaderView;
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWMainMenuTableViewCell.dw_reuseIdentifier;
    DWMainMenuTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    id<DWMainMenuItem> menuItem = self.model.items[indexPath.row];
    cell.model = menuItem;

#if SNAPSHOT
    if (menuItem.type == DWMainMenuItemType_Security) {
        cell.accessibilityIdentifier = @"menu_security_item";
    }
#endif /* SNAPSHOT */

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    id<DWMainMenuItem> menuItem = self.model.items[indexPath.row];
    [self.delegate mainMenuContentView:self didSelectMenuItem:menuItem];
}

#pragma mark - DWCurrentUserProfileViewDelegate

- (void)currentUserProfileView:(DWCurrentUserProfileView *)view showQRAction:(UIButton *)sender {
    [self.delegate mainMenuContentView:self showQRAction:sender];
}

- (void)currentUserProfileView:(DWCurrentUserProfileView *)view editProfileAction:(UIButton *)sender {
    [self.delegate mainMenuContentView:self editProfileAction:sender];
}

#pragma mark - Private

- (void)joinButtonAction:(UIButton *)sender {
    [self.delegate mainMenuContentView:self joinDashPayAction:sender];
}

@end

NS_ASSUME_NONNULL_END
