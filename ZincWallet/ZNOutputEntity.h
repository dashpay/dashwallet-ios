//
//  ZNOutputEntity.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class ZNTransactionEntity;

@interface ZNOutputEntity : NSManagedObject

@property (nonatomic, retain) NSString *address;
@property (nonatomic) int32_t n;
@property (nonatomic) int64_t txIndex;
@property (nonatomic) int64_t value;
@property (nonatomic, retain) ZNTransactionEntity *transaction;

@end
