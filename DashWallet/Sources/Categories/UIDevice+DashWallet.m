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

#import "UIDevice+DashWallet.h"

#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIDevice (DashWallet)

- (void)dw_playCoinSound {
    SystemSoundID soundID = [self.class dw_coinSoundID];
    AudioServicesPlaySystemSound(soundID);
}

#pragma mark - Private

+ (SystemSoundID)dw_coinSoundID {
    static SystemSoundID coinSound;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"coinflip"
                                             withExtension:@"aiff"];
        NSParameterAssert(url);
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)url,
                                         &coinSound);
    });
    return coinSound;
}

@end

NS_ASSUME_NONNULL_END
