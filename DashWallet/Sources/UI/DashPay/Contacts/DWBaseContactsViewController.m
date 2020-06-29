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

#import "DWBaseContactsViewController+DWProtected.h"

#import "DWUserSearchViewController.h"
#import "UIView+DWFindConstraints.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

// Some sane limit to prevent breaking layout
static NSInteger const MAX_SEARCH_LENGTH = 100;

NS_ASSUME_NONNULL_END

@implementation DWBaseContactsViewController

- (instancetype)initWithPayModel:(id<DWPayModelProtocol>)payModel
                    dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _payModel = payModel;
        _dataProvider = dataProvider;
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.disableSearchBarBecomesFirstResponderOnFirstAppearance = YES;

    [self dw_embedChild:self.stateController inContainer:self.contentView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.model start];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.model stop];
}

#pragma mark - DWContactsModelDelegate

- (void)contactsModelDidUpdate:(DWBaseContactsModel *)model {
    self.searchBar.hidden = NO;
    if (self.model.isEmpty) {
        if (self.model.isSearching) {
            [self.stateController setNoResultsLocalStateWithQuery:self.model.dataSource.trimmedQuery];
        }
        else {
            self.searchBar.hidden = YES;
            [self.stateController setPlaceholderLocalState];
        }
        [self.contentController dw_detachFromParent];
    }
    else {
        [self.contentController updateSearchingState];

        if (self.contentController.parentViewController == nil) {
            [self dw_embedChild:self.contentController inContainer:self.contentView];
        }
    }
}

#pragma mark - DWBaseContactsContentViewControllerDelegate

- (void)contactsContentViewController:(DWBaseContactsContentViewController *)controller
                        didSelectItem:(id<DWDPBasicItem>)item {
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.model searchWithQuery:self.searchBar.text];
}

- (BOOL)searchBar:(UISearchBar *)searchBar shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    NSString *resultText = [searchBar.text stringByReplacingCharactersInRange:range withString:text];
    return resultText.length <= MAX_SEARCH_LENGTH;
}

#pragma mark - DWSearchStateViewControllerDelegate

- (void)searchStateViewController:(DWSearchStateViewController *)controller buttonAction:(UIButton *)sender {
    [self addContactButtonAction];
}

#pragma mark - Keyboard

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    NSLayoutConstraint *constraint = [self.stateController.view dw_findConstraintWithAttribute:NSLayoutAttributeBottom];
    constraint.constant = height;
    [self.view layoutIfNeeded];
}

#pragma mark - Actions

- (void)addContactButtonAction {
    if (!self.model.hasBlockchainIdentity) {
        return;
    }

    DWUserSearchViewController *controller =
        [[DWUserSearchViewController alloc] initWithPayModel:self.payModel
                                                dataProvider:self.dataProvider];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
