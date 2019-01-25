//
//  DWActionTableViewCell.m
//  dashwallet
//
//  Created by Sam Westrich on 8/9/18.
//  Copyright © 2019 Aaron Voisine. All rights reserved.
//

#import "DWActionTableViewCell.h"

@implementation DWActionTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    UIView *bgColorView = [[UIView alloc] init];
    bgColorView.backgroundColor = [UIColor whiteColor];
    [self setSelectedBackgroundView:bgColorView];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    if (selected) {
        self.actionTitleLabel.textColor = [UIColor blackColor];
        self.imageView.image = self.selectedImageIcon;
    } else {
        self.actionTitleLabel.textColor = [UIColor whiteColor];
        self.imageView.image = self.imageIcon;
    }
    // Configure the view for the selected state
}

-(void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (highlighted) {
        self.actionTitleLabel.textColor = [UIColor blackColor];
        self.imageView.image = self.selectedImageIcon;
    } else {
        self.actionTitleLabel.textColor = [UIColor whiteColor];
        self.imageView.image = self.imageIcon;
    }
}

@end
