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

#import "DWContactsContentView.h"

#import "DWContactListTableViewCell.h"
#import "DWContactsModel.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

@interface DWContactsContentView () <UITableViewDataSource,
                                     UITableViewDelegate,
                                     DWContactListTableViewCellDelegate>

@property (readonly, nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) id<DWContactsDataSource> currentDataSource;

@end

@implementation DWContactsContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UITableView *tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        tableView.dataSource = self;
        tableView.delegate = self;
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 74.0;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, DW_TABBAR_NOTCH, 0.0);
        [self addSubview:tableView];
        _tableView = tableView;

        NSArray<NSString *> *cellIds = @[
            DWContactListTableViewCell.dw_reuseIdentifier,
        ];
        for (NSString *cellId in cellIds) {
            UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
            NSParameterAssert(nib);
            [tableView registerNib:nib forCellReuseIdentifier:cellId];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setNeedsLayout)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)setModel:(DWContactsModel *)model {
    _model = model;

    self.currentDataSource = model.contactsDataSource;
}

- (void)setCurrentDataSource:(id<DWContactsDataSource>)currentDataSource {
    _currentDataSource = currentDataSource;

    if (currentDataSource.isEmpty) {
        self.tableView.dataSource = self;
    }
    else {
        self.tableView.dataSource = currentDataSource;
        currentDataSource.contactsDelegate = self;
    }
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // TODO: return empty state cell
    return [UITableViewCell new];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.currentDataSource.isEmpty) {
        return;
    }

    id<DWContactItem> contact = [self.currentDataSource contactAtIndexPath:indexPath];
    [self.delegate contactsContentView:self didSelectContact:contact];
}

#pragma mark - DWContactListTableViewCellDelegate

- (void)contactListTableViewCell:(DWContactListTableViewCell *)cell
                didAcceptContact:(id<DWContactItem>)contact {
    [self.delegate contactsContentView:self didAcceptContact:contact];
}

- (void)contactListTableViewCell:(DWContactListTableViewCell *)cell
               didDeclineContact:(id<DWContactItem>)contact {
    [self.delegate contactsContentView:self didDeclineContact:contact];
}

@end
