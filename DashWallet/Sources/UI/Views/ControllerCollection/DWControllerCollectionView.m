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

#import "DWControllerCollectionView.h"

#import <objc/runtime.h>

#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CELL_ID = @"DWControllerCollectionViewCell";

@interface UICollectionViewCell (DWControllerCollection)

@property (nullable, strong, nonatomic) UIViewController *dw_contentViewController;

@end

@implementation UICollectionViewCell (DWControllerCollection)

- (nullable UIViewController *)dw_contentViewController {
    return objc_getAssociatedObject(self, @selector(dw_contentViewController));
}

- (void)setDw_contentViewController:(nullable UIViewController *)contentViewController {
    objc_setAssociatedObject(self,
                             @selector(dw_contentViewController),
                             contentViewController,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark - DWControllerCollectionView

@interface DWControllerCollectionView () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nullable, weak, nonatomic) id<UICollectionViewDelegate> realDelegate;
@property (nullable, weak, nonatomic) id<UICollectionViewDataSource> realDataSource;
@property (readonly, strong, nonatomic) NSMutableArray *displayedCells;

@end

@implementation DWControllerCollectionView

- (instancetype)initWithFrame:(CGRect)frame collectionViewLayout:(UICollectionViewLayout *)layout {
    self = [super initWithFrame:frame collectionViewLayout:layout];
    if (self) {
        [self controllerCollection_setup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self controllerCollection_setup];
    }
    return self;
}

- (void)controllerCollection_setup {
    [super setDataSource:self];
    [super setDelegate:self];

    [self registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:CELL_ID];

    _displayedCells = [NSMutableArray array];
}

- (void)dealloc {
    self.dataSource = nil;
    self.delegate = nil;
}

- (void)setDataSource:(nullable id<UICollectionViewDataSource>)dataSource {
    [super setDataSource:nil];
    self.realDataSource = dataSource != self ? dataSource : nil;
    [super setDataSource:dataSource ? self : nil];
}

- (void)setDelegate:(nullable id<UICollectionViewDelegate>)delegate {
    [super setDelegate:nil];
    self.realDelegate = delegate != self ? delegate : nil;
    [super setDelegate:delegate ? self : nil];
}

#pragma mark UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSParameterAssert(self.controllerDataSource);
    return [self.controllerDataSource numberOfItemsInControllerCollectionView:self];
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CELL_ID forIndexPath:indexPath];
    return cell;
}

#pragma mark UICollectionViewDelegate

- (void)collectionView:(DWControllerCollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.displayedCells containsObject:cell]) {
        return;
    }
    [self.displayedCells addObject:cell];

    [self configureCell:cell forIndexPath:indexPath];
    [self displayViewController:cell.dw_contentViewController contentView:cell.contentView];

    id<UICollectionViewDelegate> delegate = self.realDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        [delegate collectionView:collectionView willDisplayCell:cell forItemAtIndexPath:indexPath];
    }
}

- (void)collectionView:(DWControllerCollectionView *)collectionView
    didEndDisplayingCell:(UICollectionViewCell *)cell
      forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (![self.displayedCells containsObject:cell]) {
        return;
    }
    [self.displayedCells removeObject:cell];

    [self hideViewController:cell.dw_contentViewController];

    id<UICollectionViewDelegate> delegate = self.realDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        [delegate collectionView:collectionView didEndDisplayingCell:cell forItemAtIndexPath:indexPath];
    }
}

#pragma mark Private

- (void)configureCell:(UICollectionViewCell *)cell forIndexPath:(NSIndexPath *)indexPath {
    UIViewController *controller = [self.controllerDataSource controllerCollectionView:self
                                                                controllerForIndexPath:indexPath];
    cell.dw_contentViewController = controller;
}

- (void)displayViewController:(UIViewController *)controller contentView:(UIView *)contentView {
    if (!controller) {
        return;
    }

    if ([self.controllerDelegate respondsToSelector:@selector(controllerCollectionView:willShowController:)]) {
        [self.controllerDelegate controllerCollectionView:self willShowController:controller];
    }

    NSParameterAssert(self.containerViewController);

    [self.containerViewController dw_embedChild:controller inContainer:contentView];

    if ([self.controllerDelegate respondsToSelector:@selector(controllerCollectionView:didShowController:)]) {
        [self.controllerDelegate controllerCollectionView:self didShowController:controller];
    }
}

- (void)hideViewController:(UIViewController *)controller {
    if (!controller) {
        return;
    }

    if ([self.controllerDelegate respondsToSelector:@selector(controllerCollectionView:willHideController:)]) {
        [self.controllerDelegate controllerCollectionView:self willHideController:controller];
    }

    [controller beginAppearanceTransition:NO
                                 animated:NO];
    [controller willMoveToParentViewController:nil];
    [controller.view removeFromSuperview];
    [controller removeFromParentViewController];
    [controller endAppearanceTransition];

    if ([self.controllerDelegate respondsToSelector:@selector(controllerCollectionView:didHideController:)]) {
        [self.controllerDelegate controllerCollectionView:self didHideController:controller];
    }
}

#pragma mark Delegate Forwarder

// https://github.com/steipete/PSPDFTextView/blob/master/PSPDFTextView/PSPDFTextView.m

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [super respondsToSelector:aSelector] ||
           [self.realDataSource respondsToSelector:aSelector] ||
           [self.realDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    id delegate = self.realDelegate;
    id dataSource = self.realDataSource;

    if ([dataSource respondsToSelector:aSelector]) {
        return dataSource;
    }
    else if ([delegate respondsToSelector:aSelector]) {
        return delegate;
    }
    else {
        return [super forwardingTargetForSelector:aSelector];
    }
}

@end

NS_ASSUME_NONNULL_END
