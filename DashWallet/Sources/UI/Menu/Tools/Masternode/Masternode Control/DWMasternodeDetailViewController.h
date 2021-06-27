//
//  DWMasternodeDetailViewController.h
//  DashWallet
//
//  Created by Sam Westrich on 2/21/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSLocalMasternode, DSSimplifiedMasternodeEntry;

@interface DWMasternodeDetailViewController : UITableViewController

@property (nonatomic, strong) DSLocalMasternode *localMasternode;
@property (nonatomic, strong) DSSimplifiedMasternodeEntry *simplifiedMasternodeEntry;


@end

NS_ASSUME_NONNULL_END
