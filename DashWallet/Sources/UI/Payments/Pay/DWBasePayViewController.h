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

#import "DWDPBasicUserItem.h"
#import "DWDemoDelegate.h"
#import "DWNavigationChildViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentProcessor;
@protocol DWPayModelProtocol;
@protocol DWTransactionListDataProviderProtocol;
@protocol DWDPBasicUserItem;

@interface DWBasePayViewController : DWNavigationChildViewController

@property (nonatomic, strong) id<DWPayModelProtocol> payModel;
@property (nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;
@property (null_resettable, nonatomic, strong) DWPaymentProcessor *paymentProcessor;

@property (nonatomic, assign) BOOL demoMode;
@property (nullable, nonatomic, weak) id<DWDemoDelegate> demoDelegate;

- (void)performScanQRCodeAction;
/// Check pasteboard and pay
- (void)payToAddressAction;
/// Assume pasteboard contains needed data and pay
- (void)performPayToPasteboardAction;
- (void)performNFCReadingAction;
- (void)performPayToURL:(NSURL *)url;
- (void)performPayToUser:(id<DWDPBasicUserItem>)userItem;

- (void)handleFile:(NSData *)file;

/// This method is called after dismissal of payment result controller.
- (void)payViewControllerDidHidePaymentResultToContact:(nullable id<DWDPBasicUserItem>)contact;

- (id<DWDPBasicUserItem>)contactItem;

@end

NS_ASSUME_NONNULL_END
