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

#import "DWExploreWhereToSpendFiltersCell.h"

@interface DWExploreWhereToSpendFiltersCell ()
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *filterButton;
@end

@implementation DWExploreWhereToSpendFiltersCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
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

- (NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    self.titleLabel.text = title;
}

-(void)filterButtonAction {
    
}

-(void)configureHierarchy {
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 10;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.alignment = UIStackViewAlignmentCenter;
    [self.contentView addSubview:stackView];
    
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:20];
    [stackView addArrangedSubview:label];
    _titleLabel = label;
    
    [stackView addArrangedSubview:[UIView new]];
    
    UIButton *filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    filterButton.translatesAutoresizingMaskIntoConstraints = NO;
    filterButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    filterButton.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 10);
    filterButton.imageEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
    [filterButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [filterButton setTitle:NSLocalizedString(@"Filter", nil) forState:UIControlStateNormal];
    [filterButton setImage:[UIImage imageNamed:@"image.explore.dash.wts.filter"] forState:UIControlStateNormal];
    [filterButton addTarget:self
                    action:@selector(filterButtonAction)
          forControlEvents:UIControlEventTouchUpInside];
    [stackView addArrangedSubview:filterButton];
    _filterButton = filterButton;
    
    [NSLayoutConstraint activateConstraints:@[
        [filterButton.widthAnchor constraintEqualToConstant:90],
        
        [stackView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16]
    ]];
}

@end
