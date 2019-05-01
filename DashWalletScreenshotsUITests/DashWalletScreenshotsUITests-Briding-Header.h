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

#ifndef DashWalletScreenshotsUITests_Briding_Header_h
#define DashWalletScreenshotsUITests_Briding_Header_h

#include "DashWallet-Prefix.pch"

#if SNAPSHOT

#import <SimulatorStatusMagic/SDStatusBarManager.h>
static const bool _SNAPSHOT = 1;
// don't allow BartyCrouch to include "Carrier" string to localized
NSLocalizedString(@"Carrier", @"Carrier #bc-ignore!")

#else

static const bool _SNAPSHOT = 0;

#endif /* SNAPSHOT */

#endif /* DashWalletScreenshotsUITests_Briding_Header_h */
