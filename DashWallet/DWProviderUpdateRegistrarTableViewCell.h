//
//  DWProviderUpdateRegistrarTableViewCell.h
//  DashWallet
//
//  Created by Sam Westrich on 3/3/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BRCopyLabel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWProviderUpdateRegistrarTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet BRCopyLabel *payToAddressLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *operatorKeyLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *blockHeightLabel;

@end

NS_ASSUME_NONNULL_END
