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

#ifndef DWUIKit_h
#define DWUIKit_h

#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

#import "UIView+DWAnimations.h"
#import "CALayer+DWShadow.h"
#import "DevicesCompatibility.h"

#import "UIView+DWReuseHelper.h"

#import "UIViewController+DWEmbedding.h"

// Global UI Constants

#define DW_TABBAR_HEIGHT (DEVICE_HAS_HOME_INDICATOR ? 77.0 : 64.0)

#endif /* DWUIKit_h */
