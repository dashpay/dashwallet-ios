//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWExploreWhereToSpendItemCell.h"
#import <SDWebImage/SDWebImage.h>

@interface DWExploreWhereToSpendItemCell ()
@property(nonatomic, strong) UIImageView *logoImageView;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *subLabel;
@property(nonatomic, strong) UIImageView *paymentTypeIconView;
@end

@implementation DWExploreWhereToSpendItemCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self configureHierarchy];
    }
    return self;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureHierarchy];
    }
    
    return self;
}

-(void)updateWithMerchant:(DWExploreMerchant *)merchant {
    
    _nameLabel.text = merchant.name;
    
    if(merchant.logoURL) {
        [_logoImageView sd_setImageWithURL:[NSURL URLWithString:merchant.logoURL]];
    }else{
        _logoImageView.image = [UIImage imageNamed:@"image.explore.dash.wts.item.logo.empty"];
    }
    
    BOOL isGiftCard = merchant.paymentMethod == DWExploreMerchantPaymentMethodGiftCard;
    NSString *paymentIconName = isGiftCard ? @"image.explore.dash.wts.payment.gift-card" : @"image.explore.dash.wts.payment.dash";
    _paymentTypeIconView.image = [UIImage imageNamed:paymentIconName];

}

-(void)configureHierarchy
{
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 15;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.alignment = UIStackViewAlignmentCenter;
    [self.contentView addSubview:stackView];
    
    UIImageView *logoImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"image.explore.dash.wts.item.logo.empty"]];
    logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    logoImageView.contentMode = UIViewContentModeScaleAspectFit;
    logoImageView.layer.cornerRadius = 8.0;
    logoImageView.layer.masksToBounds = YES;
    [stackView addArrangedSubview:logoImageView];
    _logoImageView = logoImageView;
    
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:14];
    [stackView addArrangedSubview:label];
    _nameLabel = label;
    
    [stackView addArrangedSubview:[UIView new]];
    
    UIImageView *paymentTypeIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"image.explore.dash.wts.payment.dash"]];
    paymentTypeIconView.translatesAutoresizingMaskIntoConstraints = NO;
    paymentTypeIconView.contentMode = UIViewContentModeCenter;
    [stackView addArrangedSubview:paymentTypeIconView];
    _paymentTypeIconView = paymentTypeIconView;
    
    [NSLayoutConstraint activateConstraints:@[
        [logoImageView.widthAnchor constraintEqualToConstant:36],
        [logoImageView.heightAnchor constraintEqualToConstant:36],
        
        [paymentTypeIconView.widthAnchor constraintEqualToConstant:24],
        [paymentTypeIconView.heightAnchor constraintEqualToConstant:24],
        
        [stackView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16]
    ]];
}

@end
