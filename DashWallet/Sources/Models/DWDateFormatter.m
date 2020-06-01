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

#import "DWDateFormatter.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDateFormatter ()

@property (readonly, nonatomic, strong) NSDateFormatter *shortDateFormatter;
@property (readonly, nonatomic, strong) NSDateFormatter *longDateFormatter;

@end

NS_ASSUME_NONNULL_END

@implementation DWDateFormatter

+ (instancetype)sharedInstance {
    static DWDateFormatter *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLocale *locale = [NSLocale currentLocale];
        _shortDateFormatter = [[NSDateFormatter alloc] init];
        _shortDateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMdjmma"
                                                                         options:0
                                                                          locale:locale];
        _longDateFormatter = [[NSDateFormatter alloc] init];
        _longDateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyyMMMdjmma"
                                                                        options:0
                                                                         locale:locale];
    }
    return self;
}

- (NSString *)shortStringFromDate:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger nowYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger dateYear = [calendar component:NSCalendarUnitYear fromDate:date];

    NSDateFormatter *desiredFormatter = (nowYear == dateYear) ? self.shortDateFormatter : self.longDateFormatter;
    return [desiredFormatter stringFromDate:date];
}

- (NSString *)longStringFromDate:(NSDate *)date {
    return [self.longDateFormatter stringFromDate:date];
}

@end
