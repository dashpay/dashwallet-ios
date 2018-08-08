//
//  DWActionTableViewCell.h
//  dashwallet
//
//  Created by Sam Westrich on 8/9/18.
//  Copyright © 2018 Aaron Voisine. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DWActionTableViewCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UILabel *actionTitleLabel;
@property (strong, nonatomic) UIImage *imageIcon;
@property (strong, nonatomic) UIImage *selectedImageIcon;

@end
