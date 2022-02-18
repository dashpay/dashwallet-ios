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

#import "DWExploreWhereToSpendLocationServicePopup.h"
#import "UIColor+DWStyle.h"
#import "DWActionButton.h"
#import "UIFont+DWFont.h"

@interface DWExploreWhereToSpendLocationServicePopup ()
@property(nonatomic, copy) void (^continueBlock)(void);
@end

@implementation DWExploreWhereToSpendLocationServicePopup

-(instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        [self configureHierarchy];
    }
    
    return self;
}

- (void)continueButtonAction {
    self.continueBlock();
    [self removeFromSuperview];
}

- (void)configureHierarchy {
    self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.2];
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor dw_backgroundColor];
    container.layer.cornerRadius = 14.0f;
    container.layer.masksToBounds = YES;
    [self addSubview:container];
    
    UIStackView *stackView = [UIStackView new];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 15;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.distribution = UIStackViewDistributionFill;
    [container addSubview:stackView];
    
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"location.fill"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.layer.cornerRadius = 25.0f;
    iconView.layer.masksToBounds = YES;
    iconView.backgroundColor = [[UIColor dw_dashBlueColor] colorWithAlphaComponent:0.2];
    iconView.contentMode = UIViewContentModeCenter;
    iconView.tintColor = [UIColor dw_dashBlueColor];
    [stackView addArrangedSubview:iconView];
    
    UIStackView *textStackView = [UIStackView new];
    textStackView.translatesAutoresizingMaskIntoConstraints = NO;
    textStackView.alignment = UIStackViewAlignmentCenter;
    textStackView.spacing = 5;
    textStackView.axis = UILayoutConstraintAxisVertical;
    textStackView.distribution = UIStackViewDistributionFill;
    [stackView addArrangedSubview:textStackView];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    label.text = NSLocalizedString(@"Merchant search works better with Location Services turned on.", nil);
    [textStackView addArrangedSubview:label];
    
    label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    label.text = NSLocalizedString(@"Your location is used to show your position on the map, merchants in the selected redius and improve search results.", nil);
    [textStackView addArrangedSubview:label];
    
    DWActionButton *continueButton = [[DWActionButton alloc] init];
    continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    [continueButton setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
    [continueButton addTarget:self
                       action:@selector(continueButtonAction)
             forControlEvents:UIControlEventTouchUpInside];
    [stackView addArrangedSubview:continueButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [container.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [container.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:15],
        [container.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-15],
        
        [stackView.topAnchor constraintEqualToAnchor:container.topAnchor constant:20],
        [stackView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-20],
        [stackView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [stackView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        
        [iconView.widthAnchor constraintEqualToConstant:50.0f],
        [iconView.heightAnchor constraintEqualToConstant:50.0f],
        
        [continueButton.heightAnchor constraintEqualToConstant:40.0f],
        [continueButton.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [continueButton.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
    ]];
}

- (void)showInView:(UIView *)view {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.topAnchor constraintEqualToAnchor:view.topAnchor],
        [self.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
    ]];
}

+ (void)showInView:(UIView *)view completion: (void (^)(void))completion {
    DWExploreWhereToSpendLocationServicePopup *popup = [[DWExploreWhereToSpendLocationServicePopup alloc] initWithFrame:CGRectZero];
    popup.continueBlock = completion;
    [popup showInView:view.window];
}

@end
