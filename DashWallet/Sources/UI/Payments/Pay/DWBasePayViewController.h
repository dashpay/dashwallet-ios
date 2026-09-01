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

#import "DWDemoDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentInput;
@protocol DWPayModelProtocol;

@interface DWBasePayViewController : UIViewController

@property (nonatomic, strong) id<DWPayModelProtocol> payModel;

@property (nonatomic, assign) BOOL demoMode;
@property (nullable, nonatomic, weak) id<DWDemoDelegate> demoDelegate;

@property (nonatomic, assign) BOOL locksBalance;

/// Whether the QR scanner may leave the payment flow for a scanned
/// contact / invitation QR. Default YES; the lock screen overrides to NO
/// (nothing may navigate the app while it is locked).
@property (readonly, nonatomic, assign) BOOL allowsScannerCrossContextRouting;

- (void)performScanQRCodeAction;
/// Assume pasteboard contains needed data and pay
- (void)performPayToPasteboardAction;
- (void)performNFCReadingAction;
- (void)performPayToURL:(NSURL *)url;

/// Scanner completion — dismisses the scanner and processes the input.
/// Subclasses override to take ownership of the scanned input (the send
/// screen and payments landing feed their own view models instead).
- (void)didScanPaymentInput:(DWPaymentInput *)paymentInput;

@end

NS_ASSUME_NONNULL_END
