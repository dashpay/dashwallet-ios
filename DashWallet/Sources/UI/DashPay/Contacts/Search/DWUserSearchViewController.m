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

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWDashPayConstants.h"
#import "DWUIKit.h"
#import "DWUserProfileViewController.h"
#import "DWUserSearchModel.h"
#import "DWUserSearchResultViewController.h"
#import "DWUserSearchStateViewController.h"
#import "UISearchBar+DWAdditions.h"
#import "UIView+DWFindConstraints.h"
#import "UIView+DWRecursiveSubview.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchViewController () <UISearchBarDelegate, DWUserSearchModelDelegate, DWUserSearchResultViewControllerDelegate>

@property (nonatomic, assign) BOOL requiresNoNavigationBar;

@property (null_resettable, nonatomic, strong) DWUserSearchModel *model;

@property (null_resettable, nonatomic, strong) UISearchBar *searchBar;
@property (null_resettable, nonatomic, strong) UIView *contentView;

@property (null_resettable, nonatomic, strong) DWUserSearchStateViewController *stateController;
@property (null_resettable, nonatomic, strong) DWUserSearchResultViewController *resultsController;

@property (nonatomic, assign) BOOL searchBarIsFirstResponder;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchViewController

@synthesize requiresNoNavigationBar = _requiresNoNavigationBar;

- (BOOL)requiresNoNavigationBar {
    return _requiresNoNavigationBar;
}

- (void)setRequiresNoNavigationBar:(BOOL)requiresNoNavigationBar {
    _requiresNoNavigationBar = requiresNoNavigationBar;

    [self.navigationController setNavigationBarHidden:requiresNoNavigationBar animated:YES];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Add a New Contact", nil);
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.searchBar];
    [self.view addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    ]];

    [self.stateController setPlaceholderState];
    [self dw_embedChild:self.stateController inContainer:self.contentView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // pre-layout view to avoid undesired animation if the keyboard is shown while appearing
    [self.view layoutIfNeeded];
    [self ka_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Activate Search Bar initially
    if (!self.searchBarIsFirstResponder) {
        [self.searchBar becomeFirstResponder];
        self.searchBarIsFirstResponder = YES;
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.requiresNoNavigationBar ? UIStatusBarStyleDefault : UIStatusBarStyleLightContent;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13) {
        // hide semi-transparent overlays above UITextField in UISearchBar to achive basic white color
        UISearchBar *searchBar = self.searchBar;
        UITextField *searchTextField = (UITextField *)[searchBar dw_findSubviewOfClass:UITextField.class];
        UIView *searchTextFieldBackground = searchTextField.subviews.firstObject;
        [searchTextFieldBackground.subviews makeObjectsPerformSelector:@selector(setHidden:) withObject:@YES];
    }
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
    self.requiresNoNavigationBar = YES;
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (searchBar.showsCancelButton) {
            [searchBar dw_enableCancelButton];
        }
    });
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.model searchWithQuery:self.searchBar.text];

    if (self.model.trimmedQuery.length == 0) {
        [self.stateController setPlaceholderState];
    }

    [self.resultsController dw_detachFromParent];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];

    self.requiresNoNavigationBar = NO;
}

- (BOOL)searchBar:(UISearchBar *)searchBar shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    NSString *resultText = [searchBar.text stringByReplacingCharactersInRange:range withString:text];
    return resultText.length <= DW_MAX_USERNAME_LENGTH;
}

#pragma mark - DWUserSearchModelDelegate

- (void)userSearchModelDidStartSearch:(DWUserSearchModel *)model {
    if (self.model.trimmedQuery.length == 0) {
        [self.stateController setPlaceholderState];
    }
    else {
        [self.stateController setSearchingStateWithQuery:self.model.trimmedQuery];
    }
}

- (void)userSearchModel:(DWUserSearchModel *)model completedWithItems:(NSArray<id<DWContactItem>> *)items {
    if (items.count > 0) {
        self.resultsController.items = items;
        [self dw_embedChild:self.resultsController inContainer:self.contentView];
    }
    else {
        [self.resultsController dw_detachFromParent];
        [self.stateController setNoResultsStateWithQuery:self.model.trimmedQuery];
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
                  didSelectItemAtIndex:(NSInteger)index {
    DSBlockchainIdentity *blockchainIdentity = [self.model blokchainIdentityAtIndex:index];
    if (!blockchainIdentity) {
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

- (UISearchBar *)searchBar {
    if (_searchBar == nil) {
        UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
        searchBar.translatesAutoresizingMaskIntoConstraints = NO;
        searchBar.delegate = self;
        searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        searchBar.barTintColor = [UIColor dw_secondaryBackgroundColor];
        searchBar.searchBarStyle = UISearchBarStyleMinimal;
        searchBar.tintColor = [UIColor dw_dashBlueColor];
        searchBar.placeholder = NSLocalizedString(@"Search for a username", nil);
        UITextField *searchTextField = (UITextField *)[searchBar dw_findSubviewOfClass:UITextField.class];
        searchTextField.tintColor = [UIColor dw_dashBlueColor];
        searchTextField.textColor = [UIColor dw_darkTitleColor];
        searchTextField.backgroundColor = [UIColor dw_backgroundColor];
        _searchBar = searchBar;
    }
    return _searchBar;
}

- (UIView *)contentView {
    if (_contentView == nil) {
        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        _contentView = contentView;
    }
    return _contentView;
}

- (DWUserSearchStateViewController *)stateController {
    if (_stateController == nil) {
        _stateController = [[DWUserSearchStateViewController alloc] init];
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
