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

#import "DWDashPayConstants.h"

#import <DashSync/DashSync.h>

uint64_t DWDP_MIN_BALANCE_TO_CREATE_USERNAME = (DUFFS / 100) * 3; // 0.03 Dash
uint64_t DWDP_MIN_BALANCE_TO_CREATE_INVITE = (DUFFS / 100);       // 0.01 Dash
uint64_t DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME = (DUFFS / 4);   // 0.25 Dash

NSInteger DW_MIN_USERNAME_LENGTH = 3;
NSInteger DW_MIN_USERNAME_NONCONTESTED_LENGTH = 20;
NSInteger DW_MAX_USERNAME_LENGTH = 23;
BOOL MOCK_DASHPAY = YES; // TODO: remove once Platform is available

NSString *const DWDP_THUMBNAIL_SERVER = @"http://54.74.4.114";
