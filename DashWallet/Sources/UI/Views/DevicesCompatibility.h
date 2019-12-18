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

#ifndef DevicesCompatibility_h
#define DevicesCompatibility_h

#define IS_IPHONE ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
#define IS_IPAD ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)

#define SCREEN_WIDTH ([[UIScreen mainScreen] bounds].size.width)
#define SCREEN_HEIGHT ([[UIScreen mainScreen] bounds].size.height)
#define SCREEN_MAX_LENGTH (MAX(SCREEN_WIDTH, SCREEN_HEIGHT))

#define IS_IPHONE_5_OR_LESS (IS_IPHONE && SCREEN_MAX_LENGTH <= 568.0)
#define IS_IPHONE_6 (IS_IPHONE && SCREEN_MAX_LENGTH == 667.0)
#define IS_IPHONE_6_PLUS (IS_IPHONE && SCREEN_MAX_LENGTH == 736.0)
#define IS_IPHONE_X_FAMILY (IS_IPHONE && (SCREEN_MAX_LENGTH == 812.0) || (SCREEN_MAX_LENGTH == 896.0))
#define IS_IPHONE_X (IS_IPHONE && SCREEN_MAX_LENGTH == 812.0)
#define IS_IPHONE_XSMAX_OR_XR (IS_IPHONE && SCREEN_MAX_LENGTH == 896.0)

#define IS_IPAD_PRO_11 (IS_IPAD && SCREEN_MAX_LENGTH == 1194.0)
#define IS_IPAD_PRO_12_9 (IS_IPAD && SCREEN_MAX_LENGTH == 1366.0)

#define DEVICE_HAS_HOME_INDICATOR ([UIApplication sharedApplication].delegate.window.safeAreaInsets.bottom > 0)

#endif /* DevicesCompatibility_h */
