//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWFormTableViewController.h"

#import "DWPlaceholderFormTableViewCell.h"
#import "DWSelectorFormTableViewCell.h"
#import "DWSwitcherFormTableViewCell.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const SELECTOR_CELL_ID = @"DWSelectorFormTableViewCell";
static NSString *const SWITCHER_CELL_ID = @"DWSwitcherFormTableViewCell";
static NSString *const PLACEHOLDER_CELL_ID = @"DWPlaceholderFormTableViewCell";

static CGFloat const DEFAULT_CELL_HEIGHT = 44.0;

@interface DWFormTableViewController ()

@property (nullable, copy, nonatomic) NSArray<DWFormSectionModel *> *sections;
@property (nullable, copy, nonatomic) NSArray<DWFormSectionModel *> *internalDataSource;

@end

@implementation DWFormTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSArray<NSString *> *cellIds = @[
        SELECTOR_CELL_ID,
        SWITCHER_CELL_ID,
        PLACEHOLDER_CELL_ID,
    ];
    for (NSString *cellId in cellIds) {
        UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
        NSParameterAssert(nib);
        [self.tableView registerNib:nib forCellReuseIdentifier:cellId];
    }
}

- (void)setSections:(nullable NSArray<DWFormSectionModel *> *)sections placeholderText:(nullable NSString *)placeholderText {
    self.sections = sections;

    if (placeholderText) {
        BOOL hasItems = NO;
        for (DWFormSectionModel *section in sections) {
            if (section.items.count > 0) {
                hasItems = YES;
                break;
            }
        }
        if (!hasItems) {
            DWPlaceholderFormCellModel *placeholderCellModel = [[DWPlaceholderFormCellModel alloc] initWithTitle:placeholderText];
            DWFormSectionModel *placeholderSection = [[DWFormSectionModel alloc] init];
            placeholderSection.items = @[ placeholderCellModel ];
            self.internalDataSource = @[ placeholderSection ];
        }
    }

    if (!self.internalDataSource) {
        self.internalDataSource = self.sections;
    }

    [self.tableView reloadData];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.internalDataSource.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DWFormSectionModel *sectionModel = self.internalDataSource[section];
    return sectionModel.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWFormSectionModel *sectionModel = self.internalDataSource[indexPath.section];
    NSArray<DWBaseFormCellModel *> *items = sectionModel.items;
    DWBaseFormCellModel *cellModel = items[indexPath.row];

    if ([cellModel isKindOfClass:DWSelectorFormCellModel.class]) {
        DWSelectorFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SELECTOR_CELL_ID forIndexPath:indexPath];
        cell.cellModel = (DWSelectorFormCellModel *)cellModel;
        return cell;
    }
    else if ([cellModel isKindOfClass:DWSwitcherFormCellModel.class]) {
        DWSwitcherFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SWITCHER_CELL_ID forIndexPath:indexPath];
        cell.cellModel = (DWSwitcherFormCellModel *)cellModel;
        return cell;
    }
    else if ([cellModel isKindOfClass:DWPlaceholderFormCellModel.class]) {
        DWPlaceholderFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:PLACEHOLDER_CELL_ID forIndexPath:indexPath];
        cell.cellModel = (DWPlaceholderFormCellModel *)cellModel;
        return cell;
    }
    else {
        NSAssert(NO, @"Unknown cell model %@", cellModel);

        return [UITableViewCell new];
    }
}

#pragma mark UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWFormSectionModel *sectionModel = self.internalDataSource[indexPath.section];
    NSArray<DWBaseFormCellModel *> *items = sectionModel.items;
    DWBaseFormCellModel *cellModel = items[indexPath.row];

    if ([cellModel isKindOfClass:DWPlaceholderFormCellModel.class]) {
        return CGRectGetHeight(tableView.bounds);
    }
    else {
        return DEFAULT_CELL_HEIGHT;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    DWFormSectionModel *sectionModel = self.internalDataSource[section];
    NSString *sectionTitle = sectionModel.headerTitle;

    if (sectionTitle.length == 0) {
        return 0.0;
    }

    CGRect textRect = [sectionTitle boundingRectWithSize:CGSizeMake(CGRectGetWidth(tableView.frame) - 20.0, CGFLOAT_MAX)
                                                 options:NSStringDrawingUsesLineFragmentOrigin
                                              attributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:14] }
                                                 context:nil];

    return textRect.size.height + 22.0 + 10.0;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    DWFormSectionModel *sectionModel = self.internalDataSource[section];
    CGRect headerViewFrame = CGRectMake(0.0, 0.0,
                                        CGRectGetWidth(tableView.frame),
                                        [self tableView:tableView heightForHeaderInSection:section]);
    UIView *headerView = [[UIView alloc] initWithFrame:headerViewFrame];
    CGRect titleLabelFrame = CGRectMake(16.0, 10.0,
                                        headerView.frame.size.width - 20.0,
                                        headerView.frame.size.height - 12.0);
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:titleLabelFrame];

    titleLabel.text = sectionModel.headerTitle;
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor grayColor];
    headerView.backgroundColor = tableView.backgroundColor;
    [headerView addSubview:titleLabel];

    return headerView;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    DWFormSectionModel *sectionModel = self.internalDataSource[indexPath.section];
    NSArray<DWBaseFormCellModel *> *items = sectionModel.items;
    DWBaseFormCellModel *cellModel = items[indexPath.row];

    if ([cellModel isKindOfClass:DWSelectorFormCellModel.class]) {
        DWSelectorFormCellModel *selectorCellModel = (DWSelectorFormCellModel *)cellModel;
        if (selectorCellModel.didSelectBlock) {
            selectorCellModel.didSelectBlock(selectorCellModel, indexPath);
        }
    }
    else if ([cellModel isKindOfClass:DWSwitcherFormCellModel.class]) {
        // NOP
    }
}

@end

NS_ASSUME_NONNULL_END
