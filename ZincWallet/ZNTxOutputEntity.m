//
//  ZNTxOutputEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/26/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import "ZNTxOutputEntity.h"
#import "ZNTransactionEntity.h"


@implementation ZNTxOutputEntity

@dynamic transaction;

+ (instancetype)entityWithJSON:(NSDictionary *)JSON;
{
    return nil;
}

@end
