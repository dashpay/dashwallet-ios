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

#import "DWUserSearchViewController.h"

#import "DWDashPayConstants.h"
#import "DWSearchStateViewController.h"
#import "DWUIKit.h"
#import "DWUserProfileViewController.h"
#import "DWUserSearchModel.h"
#import "DWUserSearchResultViewController.h"
#import "UIView+DWFindConstraints.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchViewController () <DWUserSearchModelDelegate, DWUserSearchResultViewControllerDelegate>

@property (null_resettable, nonatomic, strong) DWUserSearchModel *model;

@property (null_resettable, nonatomic, strong) DWSearchStateViewController *stateController;
@property (null_resettable, nonatomic, strong) DWUserSearchResultViewController *resultsController;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Add a New Contact", nil);

    self.searchBar.placeholder = NSLocalizedString(@"Search for a username", nil);

    [self.stateController setPlaceholderGlobalState];
    [self dw_embedChild:self.stateController inContainer:self.contentView];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.model searchWithQuery:self.searchBar.text];

    if (self.model.trimmedQuery.length == 0) {
        [self.stateController setPlaceholderGlobalState];
    }

    [self.resultsController dw_detachFromParent];
}

- (BOOL)searchBar:(UISearchBar *)searchBar shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    NSString *resultText = [searchBar.text stringByReplacingCharactersInRange:range withString:text];
    return resultText.length <= DW_MAX_USERNAME_LENGTH;
}

#pragma mark - DWUserSearchModelDelegate

- (void)userSearchModelDidStartSearch:(DWUserSearchModel *)model {
    if (self.model.trimmedQuery.length == 0) {
        [self.stateController setPlaceholderGlobalState];
    }
    else {
        [self.stateController setSearchingStateWithQuery:self.model.trimmedQuery];
    }
}

- (void)userSearchModel:(DWUserSearchModel *)model completedWithItems:(NSArray<DWUserSearchItem *> *)items {
    if (items.count > 0) {
        self.resultsController.searchQuery = model.trimmedQuery;
        self.resultsController.items = items;
        [self dw_embedChild:self.resultsController inContainer:self.contentView];
    }
    else {
        [self.resultsController dw_detachFromParent];
        [self.stateController setNoResultsGlobalStateWithQuery:self.model.trimmedQuery];
    }
}

- (void)userSearchModel:(DWUserSearchModel *)model completedWithError:(NSError *)error {
    [self.resultsController dw_detachFromParent];
    [self.stateController setErrorStateWithError:error];
}

#pragma mark - DWUserSearchResultViewControllerDelegate

- (void)userSearchResultViewController:(DWUserSearchResultViewController *)controller
                willDisplayItemAtIndex:(NSInteger)index {
    [self.model willDisplayItemAtIndex:index];
}

- (void)userSearchResultViewController:(DWUserSearchResultViewController *)controller
                  didSelectItemAtIndex:(NSInteger)index
                                  cell:(UITableViewCell *)cell {
    DSBlockchainIdentity *blockchainIdentity = [self.model blokchainIdentityAtIndex:index];
    if (!blockchainIdentity) {
        return;
    }

    if (![self.model canOpenBlockchainIdentity:blockchainIdentity]) {
        [cell dw_shakeView];
        return;
    }

    DWUserProfileViewController *profileController =
        [[DWUserProfileViewController alloc] initWithBlockchainIdentity:blockchainIdentity];
    [self.navigationController pushViewController:profileController animated:YES];
}

#pragma mark - Keyboard

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    NSLayoutConstraint *constraint = [self.stateController.view dw_findConstraintWithAttribute:NSLayoutAttributeBottom];
    constraint.constant = height;
    [self.view layoutIfNeeded];
}

#pragma mark - Private

- (DWUserSearchModel *)model {
    if (_model == nil) {
        DWUserSearchModel *model = [[DWUserSearchModel alloc] init];
        model.delegate = self;
        _model = model;
    }
    return _model;
}

- (DWSearchStateViewController *)stateController {
    if (_stateController == nil) {
        _stateController = [[DWSearchStateViewController alloc] init];
    }
    return _stateController;
}

- (DWUserSearchResultViewController *)resultsController {
    if (_resultsController == nil) {
        _resultsController = [[DWUserSearchResultViewController alloc] init];
        _resultsController.delegate = self;
    }
    return _resultsController;
}

@end
