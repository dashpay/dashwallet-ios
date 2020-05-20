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
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "DWUserDetailsCell.h"
#import "DWUserDetailsContactCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsContentViewController () <DWUserDetailsCellDelegate>

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsContentViewController

- (void)setModel:(DWContactsModel *)model {
    _model = model;
    [model.dataSource setupWithTableView:self.tableView
                     userDetailsDelegate:self
                         emptyDataSource:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, DW_TABBAR_NOTCH, 0.0);

    NSArray<NSString *> *cellIds = @[
        DWUserDetailsCell.dw_reuseIdentifier,
    ];
    for (NSString *cellId in cellIds) {
        UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
        NSParameterAssert(nib);
        [self.tableView registerNib:nib forCellReuseIdentifier:cellId];
    }
    [self.tableView registerClass:DWUserDetailsContactCell.class
           forCellReuseIdentifier:DWUserDetailsContactCell.dw_reuseIdentifier];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // TODO: return empty state cell
    return [UITableViewCell new];
}

#pragma mark - DWUserDetailsCellDelegate

- (void)userDetailsCell:(DWUserDetailsCell *)cell didAcceptContact:(id<DWUserDetails>)contact {
    [self.model acceptContactRequest:contact];
}

- (void)userDetailsCell:(DWUserDetailsCell *)cell didDeclineContact:(id<DWUserDetails>)contact {
    NSLog(@"DWDP: ignore contact request");
}

@end
