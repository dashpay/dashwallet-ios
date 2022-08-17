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

#import "DWExploreWhereToSpendInfoViewController.h"
#import "DWUIKit.h"
#import "DWActionButton.h"
#import "DWButton.h"
#import "DWExploreGiftCardInfoViewController.h"

@interface DWExploreWhereToSpendInfoViewController ()
-(UIStackView *)merchantTypeViewFor:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage *)image;
@end

@implementation DWExploreWhereToSpendInfoViewController

-(void)learnMoreAction {
    DWExploreGiftCardInfoViewController *vc = [DWExploreGiftCardInfoViewController new];
    [self presentViewController:vc animated:YES completion:nil];
}

-(void)continueButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)configureHierarchy {
    [super configureHierarchy];
    
    UIStackView *contentView = [UIStackView new];
    contentView.axis = UILayoutConstraintAxisVertical;
    contentView.spacing = 30;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview: contentView];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle1];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    titleLabel.text = NSLocalizedString(@"We have 2 types of merchants", nil);
    [contentView addArrangedSubview:titleLabel];
    
    UIStackView *itemView;
    itemView = [self merchantTypeViewFor:NSLocalizedString(@"Accepts DASH directly", nil)
                                subtitle:NSLocalizedString(@"Pay with the DASH Wallet.", nil)
                                   image:[UIImage imageNamed:@"image.explore.dash.wts.dash"]];
    [contentView addArrangedSubview:itemView];

    UIStackView *giftCardStack = [UIStackView new];
    giftCardStack.axis = UILayoutConstraintAxisVertical;
    giftCardStack.spacing = 2;
    [contentView addArrangedSubview:giftCardStack];
    
    itemView = [self merchantTypeViewFor:NSLocalizedString(@"Buy gift cards with your Dash", nil)
                                subtitle:NSLocalizedString(@"Buy gift cards with your Dash for the exact amount of your purchase.", nil)
                                   image:[UIImage imageNamed:@"image.explore.dash.wts.card.orange"]];
    [giftCardStack addArrangedSubview:itemView];
    
    UIButton *learnMoreButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [learnMoreButton setTitle:NSLocalizedString(@"Learn More", nil) forState:UIControlStateNormal];
    [learnMoreButton setTitleColor:[UIColor dw_dashBlueColor] forState:UIControlStateNormal];
    [learnMoreButton.titleLabel setFont:[UIFont dw_fontForTextStyle:UIFontTextStyleFootnote]];
    [learnMoreButton addTarget:self
                       action:@selector(learnMoreAction)
             forControlEvents:UIControlEventTouchUpInside];
    [giftCardStack addArrangedSubview:learnMoreButton];
    
    [contentView addArrangedSubview:[UIView new]];
    
    DWActionButton *continueButton = [[DWActionButton alloc] init];
    continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    [continueButton setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
    [continueButton addTarget:self
                     action:@selector(continueButtonAction)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:continueButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:74],
        [contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:continueButton.topAnchor constant:30],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        
        [continueButton.heightAnchor constraintEqualToConstant:46],
        [continueButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-15],
        [continueButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [continueButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        
    ]];
}

-(UIStackView *)merchantTypeViewFor:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage *)image {
    UIStackView *itemStackView = [UIStackView new];
    itemStackView.axis = UILayoutConstraintAxisVertical;
    itemStackView.spacing = 10;
    itemStackView.translatesAutoresizingMaskIntoConstraints = NO;
    itemStackView.distribution = UIStackViewDistributionEqualSpacing;
    
    UIImageView *iconImageView = [[UIImageView alloc] initWithImage:image];
    iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    [itemStackView addArrangedSubview:iconImageView];
    
    UIStackView *labelsStackView = [UIStackView new];
    labelsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    labelsStackView.axis = UILayoutConstraintAxisVertical;
    labelsStackView.spacing = 1;
    labelsStackView.alignment = UIStackViewAlignmentCenter;
    [itemStackView addArrangedSubview: labelsStackView];
    
    UILabel *itemTitleLabel = [[UILabel alloc] init];
    itemTitleLabel.text = title;
    itemTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    itemTitleLabel.textColor = [UIColor labelColor];
    itemTitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    itemTitleLabel.textAlignment = NSTextAlignmentCenter;
    itemTitleLabel.numberOfLines = 0;
    [labelsStackView addArrangedSubview:itemTitleLabel];
    
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = subtitle;
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.textColor = [UIColor secondaryLabelColor];
    descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 0;
    [labelsStackView addArrangedSubview:descLabel];
    
    return itemStackView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

@end
