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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DWControllerCollectionView;

@protocol DWControllerCollectionViewDataSource <NSObject>

@required
- (NSInteger)numberOfItemsInControllerCollectionView:(DWControllerCollectionView *)view;
- (UIViewController *)controllerCollectionView:(DWControllerCollectionView *)view
                        controllerForIndexPath:(NSIndexPath *)indexPath;

@end

@protocol DWControllerCollectionViewDelegate <NSObject>

@optional
- (void)controllerCollectionView:(DWControllerCollectionView *)view
              willShowController:(UIViewController *)controller;
- (void)controllerCollectionView:(DWControllerCollectionView *)view
               didShowController:(UIViewController *)controller;
- (void)controllerCollectionView:(DWControllerCollectionView *)view
              willHideController:(UIViewController *)controller;
- (void)controllerCollectionView:(DWControllerCollectionView *)view
               didHideController:(UIViewController *)controller;

@end

@interface DWControllerCollectionView : UICollectionView

@property (nullable, weak, nonatomic) UIViewController *containerViewController;

@property (nullable, weak, nonatomic) id<DWControllerCollectionViewDataSource> controllerDataSource;
@property (nullable, weak, nonatomic) id<DWControllerCollectionViewDelegate> controllerDelegate;

@end

NS_ASSUME_NONNULL_END
