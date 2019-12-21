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

#import "DWSeedWordModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSeedWordModel ()

@property (nonatomic, assign) NSUInteger index;

@end

@implementation DWSeedWordModel

- (instancetype)initWithWord:(NSString *)word {
    NSParameterAssert(word);

    self = [super init];
    if (self) {
        _word = word;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[self class]]) {
        return NO;
    }

    return [self isEqualToWordModel:object];
}

- (BOOL)isEqualToWordModel:(DWSeedWordModel *)object {
    if (!object) {
        return NO;
    }

    return [self.word isEqualToString:object.word];
}

- (NSUInteger)hash {
    return self.word.hash;
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    typeof(self) copy = [[self.class alloc] initWithWord:self.word];
    copy.selected = self.selected;
    copy.visible = self.visible;

    return copy;
}

@end

NS_ASSUME_NONNULL_END
