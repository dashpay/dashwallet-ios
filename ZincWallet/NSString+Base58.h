//
//  NSString+Base58.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Base58)

- (NSString *)hexToBase58check;
- (NSString *)base58checkToHex;

@end
