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

#import "DWUpholdMainModel.h"

#import "DWUpholdClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdMainModel ()

@property (assign, nonatomic) DWUpholdMainModelState state;
@property (nullable, strong, nonatomic) DWUpholdCardObject *card;

@end

@implementation DWUpholdMainModel

- (void)fetch {
    self.state = DWUpholdMainModelStateLoading;
    __weak typeof(self) weakSelf = self;
    [[DWUpholdClient sharedInstance] getDashCard:^(DWUpholdCardObject *_Nullable card) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.card = card;
        strongSelf.state = card ? DWUpholdMainModelStateDone : DWUpholdMainModelStateFailed;
    }];
}

@end

NS_ASSUME_NONNULL_END
