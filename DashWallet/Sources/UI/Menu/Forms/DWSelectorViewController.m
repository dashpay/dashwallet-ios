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
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSelectorViewController ()

@property (copy, nonatomic) NSArray<id<DWSelectorFormItem>> *items;
@property (assign, nonatomic) NSUInteger selectedIndex;
@property (null_resettable, strong, nonatomic) DWFormTableViewController *formController;

@end

@implementation DWSelectorViewController

+ (instancetype)controller {
    return [[self alloc] init];
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (void)setItems:(NSArray<id<DWSelectorFormItem>> *)items
      selectedIndex:(NSUInteger)selectedIndex
    placeholderText:(nullable NSString *)placeholderText {
    self.items = items;
    self.selectedIndex = selectedIndex;

    __weak __typeof(self) weakSelf = self;

    NSMutableArray<DWSelectorFormCellModel *> *cellModels = [NSMutableArray array];
    NSUInteger index = 0;
    for (id<DWSelectorFormItem> item in items) {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:item.title];
        cellModel.accessoryType = (index == selectedIndex) ? DWSelectorFormAccessoryType_CheckmarkSelected : DWSelectorFormAccessoryType_CheckmarkEmpty;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *cellModel, NSIndexPath *indexPath) {
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
        _formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    }
    return _formController;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWFormTableViewController *formController = self.formController;
    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
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
        previousCellModel.accessoryType = DWSelectorFormAccessoryType_CheckmarkEmpty;
    }
    self.selectedIndex = [cellModels indexOfObject:cellModel];
    cellModel.accessoryType = DWSelectorFormAccessoryType_CheckmarkSelected;

    if (self.didSelectItemBlock) {
        self.didSelectItemBlock(self.items[self.selectedIndex], self.selectedIndex);
    }
}

@end

NS_ASSUME_NONNULL_END
