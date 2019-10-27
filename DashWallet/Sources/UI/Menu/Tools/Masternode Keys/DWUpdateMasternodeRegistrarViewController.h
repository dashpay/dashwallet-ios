//
//  DWUpdateMasternodeRegistrarViewController.h
//  DashWallet
//
//  Created by Sam Westrich on 2/22/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWUpdateMasternodeRegistrarViewController : UITableViewController

@property (nonatomic, strong) DSLocalMasternode *localMasternode;
@property (nonatomic, strong) DSSimplifiedMasternodeEntry *simplifiedMasternodeEntry;

@end

NS_ASSUME_NONNULL_END
