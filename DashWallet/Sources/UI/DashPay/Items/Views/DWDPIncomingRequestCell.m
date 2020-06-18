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

#import "DWDPIncomingRequestCell.h"

#import "DWDPGenericContactRequestItemView.h"

#import "DWDPNewIncomingRequestObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPIncomingRequestCell ()

@property (readonly, nonatomic, strong) DWDPGenericContactRequestItemView *itemView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPIncomingRequestCell

@dynamic itemView;
@dynamic delegate;

+ (Class)itemViewClass {
    return DWDPGenericContactRequestItemView.class;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self.itemView.acceptButton addTarget:self action:@selector(acceptButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [self.itemView.declineButton addTarget:self action:@selector(declineButtonAction) forControlEvents:UIControlEventTouchUpInside];

        [self mvvm_observe:@"item.requestState"
                      with:^(typeof(self) self, id value) {
                          [self updateItemRequestState];
                      }];
    }
    return self;
}

#pragma mark - Actions

- (void)acceptButtonAction {
    [self.delegate acceptIncomingRequest:self.item];
}

- (void)declineButtonAction {
    [self.delegate declineIncomingRequest:self.item];
}

#pragma mark - Private

- (void)updateItemRequestState {
    id<DWDPNewIncomingRequestItem> requestItem = (id<DWDPNewIncomingRequestItem>)self.item;
    self.itemView.requestState = requestItem.requestState;
}

@end
