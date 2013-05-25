//
//  ZNKey.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/22/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNKey : NSObject

@property (nonatomic, assign) NSString *privateKey;
@property (nonatomic, readonly) NSData *publicKey;
@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) NSData *hash160;

- (id)initWithPrivateKey:(NSString *)privateKey;

- (NSData *)sign:(NSData *)d;

@end
