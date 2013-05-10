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
@property (nonatomic, assign) double amount;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, readonly) NSData *signedTransaction;
@property (nonatomic, readonly, getter=isValid) BOOL valid;

+ (id)requestWithData:(NSData *)data;

- (id)initWithData:(NSData *)data;

@end
