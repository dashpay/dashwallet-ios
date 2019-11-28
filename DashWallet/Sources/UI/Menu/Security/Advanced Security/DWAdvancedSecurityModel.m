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

#import "DWAdvancedSecurityModel.h"

#import "DWGlobalOptions.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWAdvancedSecurityModel

- (instancetype)init {
    self = [super init];
    if (self) {
        DWGlobalOptions *globalOptions = [DWGlobalOptions sharedInstance];

        _lockTimerTimeInterval = @(globalOptions.autoLockAppInterval);
        NSAssert([self.lockTimerTimeIntervals indexOfObject:_lockTimerTimeInterval] != NSNotFound,
                 @"Internal inconsistency");
    }
    return self;
}

@synthesize lockTimerTimeIntervals = _lockTimerTimeIntervals;

- (NSArray<NSNumber *> *)lockTimerTimeIntervals {
    if (!_lockTimerTimeIntervals) {
        // Never (lock timer is off) / 1 min / 5 min / 1 hr / 1 day
        _lockTimerTimeIntervals = @[ @0, @60, @(60 * 5), @(60 * 60), @(60 * 60 * 24) ];
    }

    return _lockTimerTimeIntervals;
}

- (void)setLockTimerTimeInterval:(NSNumber *)lockTimerTimeInterval {
    _lockTimerTimeInterval = lockTimerTimeInterval;

    [DWGlobalOptions sharedInstance].autoLockAppInterval = lockTimerTimeInterval.integerValue;
}

- (NSString *)stringForLockTimerTimeInterval:(NSNumber *)number {
    NSInteger value = number.integerValue;
    switch (value) {
        case 0:
            return NSLocalizedString(@"Never", nil);
        case 60:
            return NSLocalizedString(@"1 min", @"Shorten version of minute");
        case (60 * 5):
            return NSLocalizedString(@"5 min", @"Shorten version of minutes");
        case (60 * 60):
            return NSLocalizedString(@"1 hour", nil);
        case (60 * 60 * 24):
            return NSLocalizedString(@"1 day", nil);
        default:
            NSAssert(NO, @"Unhandled time interval");
            return @"Unknown";
    }
}

- (NSAttributedString *)attributedStringForCurrentLockTimerTimeIntervalWithFont:(UIFont *)font {
    NSNumber *number = self.lockTimerTimeInterval;
    NSString *string = [self stringForLockTimerTimeInterval:number];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [UIColor dw_dashBlueColor],
    };

    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string
                                                                           attributes:attributes];

    return attributedString;
}

@end

NS_ASSUME_NONNULL_END
