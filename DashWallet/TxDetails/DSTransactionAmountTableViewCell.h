//
//  DSTransactionAmountTableViewCell.h
//  DashWallet
//
//  Created by Sam Westrich on 7/22/18.
//  Copyright © 2018 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DSTransactionAmountTableViewCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *amountLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;

@end
