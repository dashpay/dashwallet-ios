//
//  DWProviderUpdateServiceTableViewCell.h
//  DashWallet
//
//  Created by Sam Westrich on 3/3/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "BRCopyLabel.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWProviderUpdateServiceTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet BRCopyLabel *locationLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *operatorRewardPayoutAddressLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *blockHeightLabel;

@end

NS_ASSUME_NONNULL_END
