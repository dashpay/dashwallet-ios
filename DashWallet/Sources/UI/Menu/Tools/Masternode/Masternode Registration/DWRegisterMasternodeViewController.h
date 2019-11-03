//
//  DWRegisterMasternodeViewController.h
//  DashWallet
//
//  Created by Sam Westrich on 2/9/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWSignPayloadViewController.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWRegisterMasternodeViewController : UITableViewController <DWSignPayloadDelegate>

@property (nonatomic, strong) DSChain *chain;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
