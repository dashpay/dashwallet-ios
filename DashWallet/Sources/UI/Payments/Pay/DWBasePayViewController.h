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

- (void)performScanQRCodeAction;
/// Assume pasteboard contains needed data and pay
- (void)performPayToPasteboardAction;
- (void)performNFCReadingAction;
- (void)performPayToURL:(NSURL *)url;
/// Run an already-built payment input through the payment controller.
/// Public so Swift subclasses that shadow the QR-scan delegate can fall
/// back to the standard processing path.
- (void)processPaymentInput:(DWPaymentInput *)input;

@end

NS_ASSUME_NONNULL_END
