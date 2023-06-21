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

#import "DWMainMenuModel.h"
#import "DWMainMenuTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

#if DASHPAY
#import "DWUserProfileContainerView.h"
#import "DWDPWelcomeMenuView.h"
#import "DWDashPayReadyProtocol.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuContentView () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;

#if DASHPAY
@property (nonatomic, strong) DWUserProfileContainerView *headerView;
@property (nonatomic, strong) DWDPWelcomeMenuView *joinHeaderView;

@property (assign, nonatomic) bool hasUsername;
#endif

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

#if DASHPAY
        DWUserProfileContainerView *headerView = [[DWUserProfileContainerView alloc] initWithFrame:CGRectZero];
        headerView.delegate = self;
        _headerView = headerView;
        
        DWDPWelcomeMenuView *joinHeaderView = [[DWDPWelcomeMenuView alloc] initWithFrame:CGRectZero];
        [joinHeaderView.joinButton addTarget:self
                                      action:@selector(joinButtonAction:)
                            forControlEvents:UIControlEventTouchUpInside];
        _joinHeaderView = joinHeaderView;
#endif
        
        NSString *cellId = DWMainMenuTableViewCell.dw_reuseIdentifier;
        UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
        NSParameterAssert(nib);
        [tableView registerNib:nib forCellReuseIdentifier:cellId];
    }
    return self;
}

- (void)setModel:(DWMainMenuModel *)model {
    _model = model;

    [self.tableView reloadData];
}

- (void)layoutSubviews {
    [super layoutSubviews];

#if DASHPAY
    UIView *tableHeaderView = self.tableView.tableHeaderView;
    if (tableHeaderView) {
        CGSize headerSize = [tableHeaderView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (CGRectGetHeight(tableHeaderView.frame) != headerSize.height) {
            tableHeaderView.frame = CGRectMake(0.0, 0.0, headerSize.width, headerSize.height);
            self.tableView.tableHeaderView = tableHeaderView;
        }
    }
#endif
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

#if DASHPAY

- (void)updateUserHeader {
    //[self.userModel update]; //TODO: DashPay
    [self updateHeader];
}

- (void)updateHeader {
    UIView *header = nil;
    if(self.hasUsername) {
        header = self.headerView;
        [self.headerView update];
    } else {
        header = self.joinHeaderView;
    }
    
//    if (self.dashPayReady.isDashPayReady) {
        
//    }
//    else if (self.userModel.blockchainIdentity != nil) {
//        [self.headerView update];
//        header = self.headerView;
//    }

    self.tableView.tableHeaderView = header;
    [self setNeedsLayout];
}

#pragma mark - DWCurrentUserProfileViewDelegate

- (void)currentUserProfileView:(DWCurrentUserProfileView *)view showQRAction:(UIButton *)sender {
    [self.delegate mainMenuContentView:self showQRAction:sender];
}

- (void)currentUserProfileView:(DWCurrentUserProfileView *)view editProfileAction:(UIButton *)sender {
    [self.delegate mainMenuContentView:self editProfileAction:sender];
}

- (void)joinButtonAction:(UIButton *)sender {
    self.hasUsername = !_hasUsername;
    [self updateHeader];
    //[self.delegate mainMenuContentView:self joinDashPayAction:sender];
}
#endif
@end

NS_ASSUME_NONNULL_END
