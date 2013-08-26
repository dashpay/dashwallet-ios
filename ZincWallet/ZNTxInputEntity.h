//
//  ZNTxInputEntity.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/26/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "ZNOutputEntity.h"

@class ZNTransactionEntity;

@interface ZNTxInputEntity : ZNOutputEntity

@property (nonatomic, retain) ZNTransactionEntity *transaction;

@end
