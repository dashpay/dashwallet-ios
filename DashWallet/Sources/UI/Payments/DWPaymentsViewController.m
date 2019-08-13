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

#import "DWPaymentsViewController.h"

#import "DWControllerCollectionView.h"
#import "DWPayViewController.h"
#import "DWSegmentedControl.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWPaymentsViewControllerIndex) {
    DWPaymentsViewControllerIndex_Pay,
    DWPaymentsViewControllerIndex_Receive,
};

@interface DWPaymentsViewController () <DWControllerCollectionViewDataSource,
                                        UICollectionViewDelegateFlowLayout>

@property (strong, nonatomic) IBOutlet UILabel *navigationTitleLabel;
@property (strong, nonatomic) IBOutlet DWSegmentedControl *segmentedControl;
@property (strong, nonatomic) IBOutlet DWControllerCollectionView *controllerCollectionView;

@property (nonatomic, strong) DWPayViewController *payViewController;

@end

@implementation DWPaymentsViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Payments" bundle:nil];
    DWPaymentsViewController *controller = [storyboard instantiateInitialViewController];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];

    self.payViewController = [DWPayViewController controller];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Private

- (void)setupView {
    self.navigationTitleLabel.text = NSLocalizedString(@"Payments", nil);

    NSArray<NSString *> *items = @[
        NSLocalizedString(@"Pay", nil),
        NSLocalizedString(@"Receive", nil),
    ];
    self.segmentedControl.shouldAnimateSelection = NO;
    self.segmentedControl.items = items;
    [self.segmentedControl addTarget:self
                              action:@selector(segmentedControlAction:)
                    forControlEvents:UIControlEventValueChanged];

    self.controllerCollectionView.delegate = self;
    self.controllerCollectionView.controllerDataSource = self;
    self.controllerCollectionView.containerViewController = self;
}

#pragma mark - Actions

- (IBAction)cancelButtonAction:(id)sender {
    [self.delegate paymentsViewControllerDidCancel:self];
}

- (void)segmentedControlAction:(DWSegmentedControl *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:sender.selectedSegmentIndex inSection:0];
    [self.controllerCollectionView scrollToItemAtIndexPath:indexPath
                                          atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                  animated:YES];
}

#pragma mark DWControllerCollectionViewDataSource

- (NSInteger)numberOfItemsInControllerCollectionView:(DWControllerCollectionView *)view {
    return 2;
}

- (UIViewController *)controllerCollectionView:(DWControllerCollectionView *)view controllerForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item == DWPaymentsViewControllerIndex_Pay) {
        return self.payViewController;
    }
    else {
        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = [UIColor darkGrayColor];
        return controller;
    }
}

#pragma mark UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return collectionView.bounds.size;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    const CGFloat offset = scrollView.contentOffset.x;
    const CGFloat pageWidth = CGRectGetWidth(scrollView.bounds);
    if (pageWidth == 0.0) {
        return;
    }

    const CGFloat percent = offset / pageWidth;
    self.segmentedControl.selectedSegmentIndexPercent = percent;
}

@end

NS_ASSUME_NONNULL_END
