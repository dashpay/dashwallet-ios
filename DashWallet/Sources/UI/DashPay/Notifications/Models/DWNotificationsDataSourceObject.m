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

#import "DWNotificationsDataSourceObject.h"

#import "DWEnvironment.h"
#import "DWNotificationsSection.h"
#import "DWUIKit.h"
#import "DWUserDetailsCell.h"
#import "DWUserDetailsContactCell.h"
#import "DWUserDetailsConvertible.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsDataSourceObject ()

@property (nullable, nonatomic, weak) UITableView *tableView;
@property (nullable, nonatomic, weak) id<DWUserDetailsCellDelegate> userDetailsDelegate;

@property (nonatomic, copy) NSArray<DWNotificationsSection *> *sections;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsDataSourceObject

- (void)updateWithSections:(NSArray<DWNotificationsSection *> *)sections {
    self.sections = sections;
    [self.tableView reloadData];
}

- (void)setupWithTableView:(UITableView *)tableView
       userDetailsDelegate:(id<DWUserDetailsCellDelegate>)userDetailsDelegate {
    self.tableView = tableView;
    self.userDetailsDelegate = userDetailsDelegate;
}

- (id<DWNotificationDetails>)notificationDetailsAtIndexPath:(NSIndexPath *)indexPath {
    DWNotificationsSection *section = self.sections[indexPath.section];
    return [section notificationDetailsAtIndex:indexPath.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DWNotificationsSection *notificationsSection = self.sections[section];
    return notificationsSection.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWUserDetailsCell *cell = nil;
    if (indexPath.section == 0) {
        NSString *cellId = DWUserDetailsCell.dw_reuseIdentifier;
        cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                               forIndexPath:indexPath];
        cell.delegate = self.userDetailsDelegate;
    }
    else {
        NSString *cellId = DWUserDetailsContactCell.dw_reuseIdentifier;
        cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                               forIndexPath:indexPath];
    }

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

#pragma mark - Private

- (void)configureCell:(DWUserDetailsCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    id<DWNotificationDetails> details = [self notificationDetailsAtIndexPath:indexPath];
    //    [cell setUserDetails:userDetails highlightedText:nil];
}

@end
