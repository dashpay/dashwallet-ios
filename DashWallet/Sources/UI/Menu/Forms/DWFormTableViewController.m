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
#import "DWSharedUIConstants.h"
#import "DWSwitcherFormTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const DEFAULT_CELL_HEIGHT = 74.0;
static CGFloat const SECTION_SPACING = 10.0;

@interface DWFormTableViewController ()

@property (nullable, copy, nonatomic) NSArray<DWFormSectionModel *> *sections;
@property (nullable, copy, nonatomic) NSArray<DWFormSectionModel *> *internalDataSource;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *customCellModels;

@end

@implementation DWFormTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.customCellModels = [NSMutableDictionary dictionary];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, 0.0, 0.0);
    self.tableView.sectionHeaderHeight = SECTION_SPACING;

    NSArray<Class> *cellClasses = @[
        DWSelectorFormTableViewCell.class,
        DWSwitcherFormTableViewCell.class,
        DWPlaceholderFormTableViewCell.class,
    ];

    for (Class cellClass in cellClasses) {
        [self.tableView registerClass:cellClass forCellReuseIdentifier:NSStringFromClass(cellClass)];
    }
}

- (void)setSections:(nullable NSArray<DWFormSectionModel *> *)sections
    placeholderText:(nullable NSString *)placeholderText {
    [self setSections:sections placeholderText:placeholderText shouldReloadData:YES];
}

- (void)setSections:(nullable NSArray<DWFormSectionModel *> *)sections
     placeholderText:(nullable NSString *)placeholderText
    shouldReloadData:(BOOL)shouldReloadData {
    self.sections = sections;

    if (placeholderText) {
        BOOL hasItems = NO;
        for (DWFormSectionModel *section in sections) {
            if (section.items.count > 0) {
                hasItems = YES;
                break;
            }
        }
        if (hasItems) {
            self.internalDataSource = self.sections;
        }
        else {
            DWPlaceholderFormCellModel *placeholderCellModel = [[DWPlaceholderFormCellModel alloc] initWithTitle:placeholderText];
            DWFormSectionModel *placeholderSection = [[DWFormSectionModel alloc] init];
            placeholderSection.items = @[ placeholderCellModel ];
            self.internalDataSource = @[ placeholderSection ];
        }
    }
    else {
        self.internalDataSource = self.sections;
    }

    if (shouldReloadData) {
        [self.tableView reloadData];
    }
}

- (void)registerCustomCellModelClass:(Class)cellModelClass forCellClass:(Class)cellClass {
    NSParameterAssert(cellModelClass);
    NSParameterAssert(cellClass);

    NSAssert([cellModelClass isSubclassOfClass:DWBaseFormCellModel.class], @"Unsupported cell model class");
    NSAssert([cellClass isSubclassOfClass:DWBaseFormTableViewCell.class], @"Unsupported cell class");

    NSString *cellId = NSStringFromClass(cellClass);
    [self.tableView registerClass:cellClass forCellReuseIdentifier:cellId];

    self.customCellModels[NSStringFromClass(cellModelClass)] = cellId;
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
    DWFormCellRoundMask roundMask = [self maskForIndexPath:indexPath];

    if ([cellModel isKindOfClass:DWSelectorFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWSelectorFormTableViewCell.class);
        DWSelectorFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                            forIndexPath:indexPath];
        cell.cellModel = (DWSelectorFormCellModel *)cellModel;
        cell.roundMask = roundMask;
        return cell;
    }
    else if ([cellModel isKindOfClass:DWSwitcherFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWSwitcherFormTableViewCell.class);
        DWSwitcherFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                            forIndexPath:indexPath];
        cell.cellModel = (DWSwitcherFormCellModel *)cellModel;
        cell.roundMask = roundMask;
        return cell;
    }
    else if ([cellModel isKindOfClass:DWPlaceholderFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWPlaceholderFormTableViewCell.class);
        DWPlaceholderFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                               forIndexPath:indexPath];
        cell.cellModel = (DWPlaceholderFormCellModel *)cellModel;
        return cell;
    }
    else {
        NSString *cellModelClass = NSStringFromClass(cellModel.class);
        NSString *cellId = self.customCellModels[cellModelClass];
        if (!cellId) {
            NSAssert(NO, @"Unknown cell model %@", cellModel);

            return [UITableViewCell new];
        }

        DWBaseFormTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                        forIndexPath:indexPath];

        if ([cell respondsToSelector:@selector(setCellModel:)]) {
            [cell performSelector:@selector(setCellModel:) withObject:cellModel];
        }
        cell.roundMask = roundMask;
        return cell;
    }
}

#pragma mark UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
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
        DWSwitcherFormCellModel *switcherCellModel = (DWSwitcherFormCellModel *)cellModel;
        switcherCellModel.on = !switcherCellModel.on;
        if (switcherCellModel.didChangeValueBlock) {
            switcherCellModel.didChangeValueBlock(switcherCellModel);
        }
    }
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = self.view.backgroundColor;
    return view;
}

#pragma mark - Private

- (DWFormCellRoundMask)maskForIndexPath:(NSIndexPath *)indexPath {
    DWFormCellRoundMask mask = 0;

    if (indexPath.row == 0) {
        mask |= DWFormCellRoundMask_Top;
    }

    DWFormSectionModel *sectionModel = self.internalDataSource[indexPath.section];
    NSArray<DWBaseFormCellModel *> *items = sectionModel.items;
    if (indexPath.row == items.count - 1) {
        mask |= DWFormCellRoundMask_Bottom;
    }

    return mask;
}

@end

NS_ASSUME_NONNULL_END
