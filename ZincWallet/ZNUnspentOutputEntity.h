//
//  ZNUnspentOutputEntity.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "ZNOutputEntity.h"


@interface ZNUnspentOutputEntity : ZNOutputEntity

@property (nonatomic, retain) NSData *txHash;
@property (nonatomic, retain) NSData *script;
@property (nonatomic) int32_t confirmations;

@end
