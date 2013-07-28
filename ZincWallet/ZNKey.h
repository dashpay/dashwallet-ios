//
//  ZNKey.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/22/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNKey : NSObject

@property (nonatomic, strong) NSString *privateKey;
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) NSData *hash160;

+ (instancetype)keyWithPrivateKey:(NSString *)privateKey;
+ (instancetype)keyWithSecret:(NSData *)secret compressed:(BOOL)compressed;
+ (instancetype)keyWithPublicKey:(NSData *)publicKey;

- (instancetype)initWithPrivateKey:(NSString *)privateKey;
- (instancetype)initWithSecret:(NSData *)secret compressed:(BOOL)compressed;
- (instancetype)initWithPublicKey:(NSData *)publicKey;

- (NSData *)sign:(NSData *)d;
- (BOOL)verify:(NSData *)d signature:(NSData *)sig;

@end
