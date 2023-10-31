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

#import "DSBlockchainIdentity+DWDisplayTitleSubtitle.h"

#import <DashSync/DashSync.h>

#import "DWUIKit.h"

@implementation DSBlockchainIdentity (DWDisplayTitleSubtitle)

- (NSAttributedString *)dw_asTitleSubtitle {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];
    NSString *title = nil;
    NSString *subtitle = nil;
    if (self.displayName != nil) {
        title = self.displayName;
        subtitle = self.currentDashpayUsername;
    }
    else {
        title = self.currentDashpayUsername;
    }
    if (title != nil) {
        [result appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:title
                                               attributes:@{
                                                   NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3],
                                                   NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
                                               }]];
    }
    if (subtitle != nil) {
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:subtitle
                                               attributes:@{
                                                   NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
                                                   NSForegroundColorAttributeName : [UIColor dw_tertiaryTextColor],
                                               }]];
    }
    [result endEditing];
    return result;
}

@end
