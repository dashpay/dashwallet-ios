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

#import "DWSecrets.h"

@implementation DWSecrets

+ (NSString *)iCloudAPIKey {
#if DEBUG
    return @"0f3e9bfdc516b5bc912241c02203005c10d4aeebb6a238c6cd452e90522ff81a";
#else
    return @"8948fbbfdb3df2d1080bcf96163716d6721a2f7b55176b47693ae5ed09749052";
#endif
}

@end
