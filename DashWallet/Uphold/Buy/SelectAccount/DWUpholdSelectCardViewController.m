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

#import "DWUpholdSelectCardViewController.h"

#import "DWUpholdCardTableViewCell.h"
#import "DWUpholdSelectCardModel.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CardTableViewCellId = @"CardTableViewCell";

@interface DWUpholdSelectCardViewController () <UITableViewDelegate, UITableViewDataSource>

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;

@property (strong, nonatomic) DWUpholdSelectCardModel *model;

@end

@implementation DWUpholdSelectCardViewController

@synthesize providedActions = _providedActions;

+ (instancetype)controllerWithCards:(NSArray<DWUpholdCardObject *> *)fiatCards {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdSelectCardStoryboard" bundle:nil];
    DWUpholdSelectCardViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdSelectCardModel alloc] initWithFiatCards:fiatCards];

    return controller;
}

- (NSArray<DWAlertAction *> *)providedActions {
    if (!_providedActions) {
        __weak typeof(self) weakSelf = self;
        DWAlertAction *cancelAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:DWAlertActionStyleCancel handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf cancelButtonAction];
        }];
        _providedActions = @[ cancelAction ];
    }
    return _providedActions;
}

- (DWAlertAction *)preferredAction {
    return self.providedActions.firstObject;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Select Card", nil);
}

#pragma mark - Actions

- (void)cancelButtonAction {
    [self.delegate upholdSelectCardViewControllerDidCancel:self];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWUpholdCardTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CardTableViewCellId forIndexPath:indexPath];
    DWUpholdCardCellModel *cellModel = self.model.items[indexPath.row];
    cell.cellModel = cellModel;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DWUpholdCardCellModel *cellModel = self.model.items[indexPath.row];
    [self.delegate upholdSelectCardViewController:self didSelectCard:cellModel.cardObject];
}

@end

NS_ASSUME_NONNULL_END
