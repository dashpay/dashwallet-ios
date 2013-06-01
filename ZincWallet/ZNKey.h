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
@property (nonatomic, assign) NSData *publicKey;
@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) NSData *hash160;

+ (id)keyWithPrivateKey:(NSString *)privateKey;
+ (id)keyWithSecret:(NSData *)secret compressed:(BOOL)compressed;
+ (id)keyWithPublicKey:(NSData *)publicKey;

- (id)initWithPrivateKey:(NSString *)privateKey;
- (id)initWithSecret:(NSData *)secret compressed:(BOOL)compressed;
- (id)initWithPublicKey:(NSData *)publicKey;

- (NSData *)sign:(NSData *)d;

@end
