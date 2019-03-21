//  
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWUpholdAmountObject.h"

#import "DWAmountObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWUpholdAmountObject

@synthesize dashAttributedString=_dashAttributedString;
@synthesize localCurrencyAttributedString=_localCurrencyAttributedString;

- (instancetype)initWithDashInternalRepresentation:(NSString *)dashInternalRepresentation
                       localInternalRepresentation:(NSString *)localInternalRepresentation
                            localCurrencyFormatted:(NSString *)localCurrencyFormatted {
    self = [super init];
    if (self) {
        if (dashInternalRepresentation.length == 0) {
            dashInternalRepresentation = @"0";
        }
        if (localInternalRepresentation.length == 0) {
            localInternalRepresentation = @"0";
        }
        
        _dashInternalRepresentation = dashInternalRepresentation;
        _localInternalRepresentation = localInternalRepresentation;
        
        // TODO: format dash value
        
        _localCurrencyAttributedString = [DWAmountObject attributedStringForLocalCurrencyFormatted:localCurrencyFormatted
                                                                                         textColor:[UIColor blackColor]];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
