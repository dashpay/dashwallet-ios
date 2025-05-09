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

#import "DWNavigationAppearance.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWCurrencyPickerPresentationMode) {
    DWCurrencyPickerPresentationMode_Dialog,
    DWCurrencyPickerPresentationMode_Screen,
};

@class DWLocalCurrencyViewController;

@protocol DWLocalCurrencyViewControllerDelegate <NSObject>

- (void)localCurrencyViewController:(DWLocalCurrencyViewController *)controller
                  didSelectCurrency:(NSString *)currencyCode;
- (void)localCurrencyViewControllerDidCancel:(DWLocalCurrencyViewController *)controller;

@end

@interface DWLocalCurrencyViewController : UITableViewController

@property (nullable, nonatomic, weak) id<DWLocalCurrencyViewControllerDelegate> delegate;
@property (nonatomic, assign) BOOL isGlobal;

- (instancetype)initWithNavigationAppearance:(DWNavigationAppearance)navigationAppearance
                            presentationMode:(DWCurrencyPickerPresentationMode)mode
                                currencyCode:(nullable NSString *)currencyCode;

@end

NS_ASSUME_NONNULL_END
