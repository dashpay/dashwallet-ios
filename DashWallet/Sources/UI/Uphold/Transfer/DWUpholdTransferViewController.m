//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWUpholdTransferViewController.h"

#import "DWUpholdAmountModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdTransferViewController ()

@property (readonly, nonatomic, strong) DWUpholdAmountModel *upholdAmountModel;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpholdTransferViewController

- (instancetype)initWithCard:(DWUpholdCardObject *)card {
    DWUpholdAmountModel *model = [[DWUpholdAmountModel alloc] initWithCard:card];

    self = [super initWithModel:model];
    if (self) {
    }
    return self;
}

- (DWUpholdAmountModel *)upholdAmountModel {
    return (DWUpholdAmountModel *)self.model;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Transfer", @"A verb, button title.");
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Uphold", nil);

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self.upholdAmountModel resetAttributedValues];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self.upholdAmountModel resetAttributedValues];
}

@end
