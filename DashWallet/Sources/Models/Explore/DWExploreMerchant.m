//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

#import "DWExploreMerchant.h"

@implementation DWExploreMerchant

- (instancetype)initWithName:(NSString *)name logoURL:(NSString *)logoURL method:(DWExploreMerchantPaymentMethod)method;
{
    self = [super init];
    if (self) {
        self.name = name;
        self.logoURL = logoURL;
        self.paymentMethod = method;
    }
    return self;
}

+ (NSArray<DWExploreMerchant *>*)mockData
{
    [[DWExploreMerchant alloc] initWithName:@"Automercados Gama" logoURL:@"https://drive.google.com/uc?export=view&id=1WYG5ijAkVYD5_If1Kjrnr7IcFqReIg20" method:DWExploreMerchantPaymentMethodDash];
    
    return @[
        [[DWExploreMerchant alloc] initWithName:@"Automercados Gama" logoURL:@"https://drive.google.com/uc?export=view&id=1WYG5ijAkVYD5_If1Kjrnr7IcFqReIg20" method:DWExploreMerchantPaymentMethodDash],
        [[DWExploreMerchant alloc] initWithName:@"1-800 Baskets" logoURL:@"https://api.giftango.com/imageservice/Images/530764_logo_600x380.png" method:DWExploreMerchantPaymentMethodGiftCard],
    ];
}

@end
