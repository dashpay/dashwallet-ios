//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWTextField.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DWInvitationActionsView;

@protocol DWInvitationActionsViewDelegate <NSObject>

- (void)invitationActionsView:(DWInvitationActionsView *)view didChangeTag:(NSString *)tag;
- (void)invitationActionsViewCopyButtonAction:(DWInvitationActionsView *)view;

@end

@interface DWInvitationActionsView : UIView

@property (nonatomic, strong) DWTextField *tagTextField;
@property (nullable, nonatomic, weak) id<DWInvitationActionsViewDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
