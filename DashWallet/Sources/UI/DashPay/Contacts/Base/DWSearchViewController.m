//
//  Created by administrator
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

#import "DWSearchViewController.h"

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWUIKit.h"
#import "UISearchBar+DWAdditions.h"
#import "UIView+DWRecursiveSubview.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSearchViewController ()

@property (nonatomic, assign) BOOL requiresNoNavigationBar;
@property (nonatomic, assign) BOOL searchBarIsFirstResponder;

@end

NS_ASSUME_NONNULL_END

@implementation DWSearchViewController

@synthesize searchBar = _searchBar;
@synthesize contentView = _contentView;

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
    // To be overriden
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
    return YES;
}

#pragma mark - Keyboard

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    // To be overriden
}

#pragma mark - Private

- (UISearchBar *)searchBar {
    if (_searchBar == nil) {
        UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
        searchBar.translatesAutoresizingMaskIntoConstraints = NO;
        searchBar.delegate = self;
        searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        searchBar.barTintColor = [UIColor dw_secondaryBackgroundColor];
        searchBar.searchBarStyle = UISearchBarStyleMinimal;
        searchBar.tintColor = [UIColor dw_dashBlueColor];
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

@end
