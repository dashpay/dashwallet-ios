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

#import "DWBasePayViewController.h"

#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSUInteger, DWLockScreenViewControllerUnlockMode) {
    DWLockScreenViewControllerUnlockMode_Instantly,
    DWLockScreenViewControllerUnlockMode_ApplicationDidBecomeActive,
};

@class DWLockScreenViewController;
@protocol DWReceiveModelProtocol;

@protocol DWLockScreenViewControllerDelegate <NSObject>

- (void)lockScreenViewControllerDidUnlock:(DWLockScreenViewController *)controller;
/// A code scanned on the lock screen, held until this lock screen unlocks: Send opens for it once, over the unlocked
/// app, whichever of the lock screen's own unlocks (its keypad or biometrics) the holder uses.
- (void)lockScreenViewController:(DWLockScreenViewController *)controller
    didHoldScannedInputForUnlock:(DWPaymentInput *)paymentInput;
/// The support-assisted global wipe has already completed successfully.
- (void)lockScreenViewControllerDidWipe:(DWLockScreenViewController *)controller;

@end

@interface DWLockScreenViewController : DWBasePayViewController <DWNavigationFullscreenable>

@property (nonatomic, assign) DWLockScreenViewControllerUnlockMode unlockMode;
@property (nullable, nonatomic, weak) id<DWLockScreenViewControllerDelegate> delegate;

+ (instancetype)lockScreenWithUnlockMode:(DWLockScreenViewControllerUnlockMode)unlockMode
                                payModel:(id<DWPayModelProtocol>)payModel;
@end

NS_ASSUME_NONNULL_END
