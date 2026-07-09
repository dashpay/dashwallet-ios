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

#import "DWContainerViewController.h"

#import "DWDemoDelegate.h"
#import "DWRootProtocol.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted by DWAppRootViewController once the lock screen has been dismissed
/// after a successful PIN / biometric unlock. Not posted when the lock screen
/// is disabled or was never required this session.
extern NSNotificationName const DWAppDidUnlockNotification;

@interface DWAppRootViewController : DWContainerViewController

@property (readonly, nonatomic, assign) BOOL demoMode;
@property (nullable, nonatomic, weak) id<DWDemoDelegate> demoDelegate;

- (instancetype)initWithModel:(id<DWRootProtocol>)model NS_DESIGNATED_INITIALIZER;

+ (Class)mainControllerClass;

- (void)setLaunchingAsDeferredController;

#if DASHPAY
- (void)handleDeeplink:(NSURL *)url;
#endif
- (void)handleURL:(NSURL *)url;

- (void)openPaymentsScreen;
- (void)closePaymentsScreen;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
