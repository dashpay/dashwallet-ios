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

#import "DWSelectorViewController.h"

#import "DWFormTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSelectorViewController ()

@property (assign, nonatomic) NSUInteger selectedIndex;
@property (strong, nonatomic) DWFormTableViewController *formController;

@end

@implementation DWSelectorViewController

+ (instancetype)controller {
    return [[self alloc] init];
}

- (void)setItems:(NSArray<NSString *> *)items selectedIndex:(NSUInteger)selectedIndex placeholderText:(nullable NSString *)placeholderText {
    self.selectedIndex = selectedIndex;

    __weak __typeof(self) weakSelf = self;

    NSMutableArray<DWSelectorFormCellModel *> *cellModels = [NSMutableArray array];
    NSUInteger index = 0;
    for (NSString *item in items) {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:item];
        cellModel.accessoryType = (index == selectedIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf didSelectCellModel:cellModel];
        };
        [cellModels addObject:cellModel];

        index += 1;
    }

    DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
    section.items = cellModels;
    [self.formController setSections:@[ section ] placeholderText:placeholderText];
}

- (DWFormTableViewController *)formController {
    if (!_formController) {
        _formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    }
    return _formController;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    DWFormTableViewController *formController = self.formController;
    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.selectedIndex != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.selectedIndex inSection:0];
        [self.formController.tableView scrollToRowAtIndexPath:indexPath
                                             atScrollPosition:UITableViewScrollPositionMiddle
                                                     animated:NO];
    }
}

#pragma mark - Private

- (void)didSelectCellModel:(DWSelectorFormCellModel *)cellModel {
    NSArray<DWSelectorFormCellModel *> *cellModels = (NSArray<DWSelectorFormCellModel *> *)self.formController.sections.firstObject.items;
    NSParameterAssert(cellModels);

    if (self.selectedIndex != NSNotFound) {
        DWSelectorFormCellModel *previousCellModel = cellModels[self.selectedIndex];
        previousCellModel.accessoryType = UITableViewCellAccessoryNone;
    }
    self.selectedIndex = [cellModels indexOfObject:cellModel];
    cellModel.accessoryType = UITableViewCellAccessoryCheckmark;

    if (self.didSelectItemBlock) {
        self.didSelectItemBlock(cellModel.title, self.selectedIndex);
    }
}

@end

NS_ASSUME_NONNULL_END
