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
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
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

    NSMutableArray<DWFormSectionModel *> *sections = [NSMutableArray array];
    NSUInteger index = 0;
    for (id<DWSelectorFormItem> item in items) {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:item.title];
        cellModel.accessoryType = (index == selectedIndex) ? DWSelectorFormAccessoryType_CheckmarkSelected : DWSelectorFormAccessoryType_CheckmarkEmpty;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *cellModel, NSIndexPath *indexPath) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf didSelectCellModel:cellModel inSection:section];
        };

        section.items = @[ cellModel ];
        [sections addObject:section];

        index += 1;
    }

    [self.formController setSections:sections placeholderText:placeholderText];
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
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:self.selectedIndex];
        [self.formController.tableView scrollToRowAtIndexPath:indexPath
                                             atScrollPosition:UITableViewScrollPositionMiddle
                                                     animated:NO];
    }
}

#pragma mark - Private

- (void)didSelectCellModel:(DWSelectorFormCellModel *)cellModel inSection:(DWFormSectionModel *)section {
    NSArray<DWFormSectionModel *> *sections = self.formController.sections;
    NSParameterAssert(sections);

    if (self.selectedIndex != NSNotFound) {
        DWFormSectionModel *previousSection = sections[self.selectedIndex];
        DWSelectorFormCellModel *previousCellModel = (DWSelectorFormCellModel *)previousSection.items.firstObject;
        previousCellModel.accessoryType = DWSelectorFormAccessoryType_CheckmarkEmpty;
    }
    self.selectedIndex = [sections indexOfObject:section];
    cellModel.accessoryType = DWSelectorFormAccessoryType_CheckmarkSelected;

    if (self.didSelectItemBlock) {
        self.didSelectItemBlock(self.items[self.selectedIndex], self.selectedIndex);
    }
}

@end

NS_ASSUME_NONNULL_END
