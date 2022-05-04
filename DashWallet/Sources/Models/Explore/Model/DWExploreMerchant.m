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

- (instancetype)initWithName:(NSString *)name
                    deeplink:(NSString * _Nullable)deeplink
                     logoURL:(NSString *)logoURL
                     address:(NSString * _Nullable)address
                     phone:(NSString * _Nullable)phone
                     website:(NSString * _Nullable)website
                    latitude:(CGFloat)latitude
                   longitude:(CGFloat)longitude
                      method:(DWExploreMerchantPaymentMethod)method
                      type:(DWExploreMerchantType)type
{
    self = [super init];
    if (self) {
        self.name = name;
        self.deeplink = deeplink;
        self.logoURL = logoURL;
        self.address = address;
        self.paymentMethod = method;
        self.phone = phone;
        self.website = website;
        self.latitude = latitude;
        self.longitude = longitude;
        self.type = type;
    }
    return self;
}

-(BOOL)isOnlineMerchant
{
    return _type == DWExploreMerchantTypeOnline;
}

+ (NSArray<DWExploreMerchant *>*)mockData
{
    return @[
        [[DWExploreMerchant alloc] initWithName:@"Automercados Gama"
                                       deeplink:nil
                                        logoURL:@"https://drive.google.com/uc?export=view&id=1WYG5ijAkVYD5_If1Kjrnr7IcFqReIg20"
                                        address:nil
                                          phone:@"58 (212) 263 19 07"
                                        website:@"https://www.a1win.net"
                                       latitude:CGFLOAT_MAX
                                      longitude:CGFLOAT_MAX
                                         method:DWExploreMerchantPaymentMethodDash
                                           type:DWExploreMerchantTypeOnline],
        [[DWExploreMerchant alloc] initWithName:@"1-800 Baskets"
                                       deeplink:@"https://dashdirect.page.link/800Flowers"
                                        logoURL:@"https://drive.google.com/uc?export=view&id=1WYG5ijAkVYD5_If1Kjrnr7IcFqReIg20"
                                        address:@"21690 Farm to Market 1093, Richmond, TX 77407, USA"
                                          phone:@"58 (212) 263 19 07"
                                        website:@"https://www.a1win.net"
                                       latitude:CGFLOAT_MAX
                                      longitude:CGFLOAT_MAX
                                         method:DWExploreMerchantPaymentMethodGiftCard
                                           type:DWExploreMerchantTypePhysical],
        [[DWExploreMerchant alloc] initWithName:@"AMC Theatres"
                                       deeplink:@"https://dashdirect.page.link/AMC"
                                        logoURL:@"https://craypaystorage.blob.core.windows.net/prod/content/wp-content/uploads/2018/05/AMC.png"
                                        address:@"13649 North Litchfield Road, USA"
                                          phone:@"58 (212) 263 19 07"
                                        website:@"https://www.a1win.net"
                                       latitude:71.2887248
                                      longitude:-156.7845987
                                         method:DWExploreMerchantPaymentMethodGiftCard
                                           type:DWExploreMerchantTypePhysical],
        
    ];
}

@end
