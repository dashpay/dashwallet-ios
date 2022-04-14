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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWExploreMerchantPaymentMethod) {
    DWExploreMerchantPaymentMethodDash,
    DWExploreMerchantPaymentMethodGiftCard,
};

typedef NS_ENUM(NSUInteger, DWExploreMerchantType) {
    DWExploreMerchantTypeOnline,
    DWExploreMerchantTypePhysical,
};

@interface DWExploreMerchant : NSObject

@property(nonatomic, assign) NSUInteger merchantId;
@property(nonatomic, strong) NSString *_Nullable name;
@property(nonatomic, strong) NSString *_Nullable deeplink;
@property(nonatomic, strong) NSString *_Nullable logoURL;
@property(nonatomic, strong) NSString *_Nullable plusCode;
@property(nonatomic, strong) NSString *_Nullable address;
@property(nonatomic, strong) NSString *_Nullable phone;
@property(nonatomic, strong) NSString *_Nullable website;
@property(nonatomic, assign) CGFloat latitude;
@property(nonatomic, assign) CGFloat longitude;

@property(nonatomic, strong) NSString *_Nullable addDate;

@property(nonatomic, strong) NSString *_Nullable updateDate;
@property(nonatomic, assign) DWExploreMerchantPaymentMethod paymentMethod;
@property(nonatomic, assign) DWExploreMerchantType type;
@property(readonly) BOOL isOnlineMerchant;

- (instancetype)initWithName:(NSString *)name
                     logoURL:(NSString *)logoURL
                     address:(NSString * _Nullable)address
                       phone:(NSString * _Nullable)phone
                     website:(NSString * _Nullable)website
                    latitude:(CGFloat)latitude
                   longitude:(CGFloat)longitude
                      method:(DWExploreMerchantPaymentMethod)method
                        type:(DWExploreMerchantType)type;
+ (NSArray<DWExploreMerchant *>*)mockData;

@end

NS_ASSUME_NONNULL_END
