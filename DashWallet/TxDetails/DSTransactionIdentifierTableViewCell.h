//
//  DSTransactionIdentifierTableViewCell.h
//  DashWallet
//
//  Created by Sam Westrich on 7/22/18.
//  Copyright © 2018 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BRCopyLabel.h"

@interface DSTransactionIdentifierTableViewCell : UITableViewCell
@property (strong, nonatomic) IBOutlet BRCopyLabel *identifierLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *titleLabel;

@end
