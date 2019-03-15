//
//  DWMasternodeTableViewCell.h
//  DashWallet
//
//  Created by Sam Westrich on 6/10/18.
//  Copyright © 2018 Dash Core Group. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DWMasternodeTableViewCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *masternodeLocationLabel;
@property (strong, nonatomic) IBOutlet UILabel *protocolLabel;
@property (strong, nonatomic) IBOutlet UILabel *outputLabel;

@end
