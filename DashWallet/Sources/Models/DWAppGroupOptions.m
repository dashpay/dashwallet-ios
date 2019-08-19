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

#import "DWAppGroupOptions.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const DW_APP_GROUP = @"group.org.dashfoundation.dash";

@implementation DWAppGroupOptions

@dynamic receiveAddress;
@dynamic receiveRequestData;
@dynamic receiveQRImageData;

+ (instancetype)sharedInstance {
    static DWAppGroupOptions *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:DW_APP_GROUP];
    self = [super initWithUserDefaults:userDefaults defaults:nil];
    return self;
}

#pragma mark - DSDynamicOptions

- (NSString *)defaultsKeyForPropertyName:(NSString *)propertyName {
    // Backwards compatibility
    if ([propertyName isEqualToString:DW_KEYPATH(self, receiveAddress)]) {
        return @"kBRSharedContainerDataWalletReceiveAddressKey";
    }
    else if ([propertyName isEqualToString:DW_KEYPATH(self, receiveRequestData)]) {
        return @"kBRSharedContainerDataWalletRequestDataKey";
    }

    return [NSString stringWithFormat:@"DW_SHARED_%@", propertyName];
}

#pragma mark - Public

- (void)restoreToDefaults {
    self.receiveAddress = nil;
    self.receiveRequestData = nil;
    self.receiveQRImageData = nil;
}

@end

NS_ASSUME_NONNULL_END
