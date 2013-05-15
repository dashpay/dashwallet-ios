//
//  NSData+Hash.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Hash)

//- (NSData *)RMD160;
- (NSData *)SHA256;
- (NSData *)SHA256_2;

@end
