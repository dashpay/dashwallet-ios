//
//  ZNPaymentRequest.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/9/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNPaymentRequest : NSObject

@property (nonatomic, strong) NSString *paymentAddress;
@property (nonatomic, strong) NSString *label;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, readonly, getter=isValid) BOOL valid;

+ (instancetype)requestWithData:(NSData *)data;
+ (instancetype)requestWithString:(NSString *)string;
+ (instancetype)requestWithURL:(NSURL *)url;

- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithURL:(NSURL *)url;

@end
