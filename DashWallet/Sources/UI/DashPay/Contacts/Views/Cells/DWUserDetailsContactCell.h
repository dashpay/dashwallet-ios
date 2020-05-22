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

#import <UIKit/UIKit.h>

#import "DWUserDetails.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserDetailsContactCell : UITableViewCell

@property (readonly, nullable, nonatomic, strong) id<DWUserDetails> userDetails;

- (void)setUserDetails:(id<DWUserDetails>)userDetails highlightedText:(nullable NSString *)highlightedText;

@end

NS_ASSUME_NONNULL_END
