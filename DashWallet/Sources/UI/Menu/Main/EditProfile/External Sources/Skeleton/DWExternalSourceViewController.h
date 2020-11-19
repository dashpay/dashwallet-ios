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

#import <UIKit/UIKit.h>

#import "DWAvatarExternalSourceConfig.h"

NS_ASSUME_NONNULL_BEGIN

@class DWExternalSourceViewController;

@protocol DWExternalSourceViewControllerDelegate <NSObject>

- (void)externalSourceViewController:(DWExternalSourceViewController *)controller
                        didLoadImage:(UIImage *)image
                                 url:(NSURL *)url
                          shouldCrop:(BOOL)shouldCrop;

@end

@interface DWExternalSourceViewController : UIViewController

@property (nullable, nonatomic, weak) id<DWExternalSourceViewControllerDelegate> delegate;

- (DWAvatarExternalSourceConfig *)config;

- (void)performLoad:(NSString *)urlString;
- (BOOL)isInputValid:(NSString *)input;

- (void)showError:(NSString *)error;
- (void)showDefaultSubtitle;
- (void)showLoadingView;
- (void)cancelLoading;

@end

NS_ASSUME_NONNULL_END
