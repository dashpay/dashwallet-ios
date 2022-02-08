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

#import "DWExploreWhereToSpendSegmentedCell.h"

@interface DWExploreWhereToSpendSegmentedCell ()

@end

@implementation DWExploreWhereToSpendSegmentedCell
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

-(void)segmentedControlAction {
    
}

-(void)configureHierarchy {
    NSArray *itemArray = [NSArray arrayWithObjects: @"One", @"Two", @"Three", nil];
    UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:itemArray];
    segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [segmentedControl addTarget:self action:@selector(segmentedControlAction) forControlEvents: UIControlEventValueChanged];
    segmentedControl.selectedSegmentIndex = 0;
    [self.contentView addSubview:segmentedControl];
    _segmentedControl = segmentedControl;
    
    [NSLayoutConstraint activateConstraints:@[
        [segmentedControl.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        //[segmentedControl.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [segmentedControl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [segmentedControl.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16]
    ]];
}

@end
