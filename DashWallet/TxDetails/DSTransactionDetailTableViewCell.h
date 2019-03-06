//
//  DSTransactionDetailTableViewCell.h
//  DashSync_Example
//
//  Created by Sam Westrich on 7/22/18.
//  Copyright © 2018 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BRCopyLabel.h"

@interface DSTransactionDetailTableViewCell : UITableViewCell
@property (strong, nonatomic) IBOutlet BRCopyLabel *addressLabel;
@property (strong, nonatomic) IBOutlet UILabel *typeInfoLabel;
@property (strong, nonatomic) IBOutlet UILabel *amountLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatAmountLabel;

@end
