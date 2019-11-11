//
//  DWRegisterMasternodeViewController.h
//  DashWallet
//
//  Created by Sam Westrich on 2/9/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWSignPayloadViewController.h"
#import <KVO-MVVM/KVOUIViewController.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWRegisterMasternodeViewController : KVOUIViewController <DWSignPayloadDelegate>

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
