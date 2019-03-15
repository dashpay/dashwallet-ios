//
//  DWTransactionTableViewCell.h
//  DashWallet
//
//  Created by Sam Westrich on 6/22/18.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DWTransactionTableViewCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *transactionLabel;
@property (strong, nonatomic) IBOutlet UILabel *directionLabel;
@property (strong, nonatomic) IBOutlet UILabel *amountLabel;
@property (strong, nonatomic) IBOutlet UILabel *dateLabel;
@property (strong, nonatomic) IBOutlet UILabel *confirmationsLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *remainingAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *remainingFiatAmountLabel;
@property (strong, nonatomic) IBOutlet UIImageView *shapeshiftImageView;

@end
