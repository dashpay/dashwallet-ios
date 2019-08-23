//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWSwitcherFormTableViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSwitcherFormTableViewCell ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UISwitch *switcher;

@end

@implementation DWSwitcherFormTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    [self mvvm_observe:@"cellModel.title" with:^(__typeof(self) self, NSString * value) {
        self.titleLabel.text = value;
    }];

    [self mvvm_observe:@"cellModel.on" with:^(__typeof(self) self, NSNumber * value) {
        [self.switcher setOn:value.boolValue animated:NO];
    }];
}

- (IBAction)switcherAction:(UISwitch *)sender {
    self.cellModel.on = sender.on;
    if (self.cellModel.didChangeValueBlock) {
        self.cellModel.didChangeValueBlock(self.cellModel);
    }
}

@end

NS_ASSUME_NONNULL_END
