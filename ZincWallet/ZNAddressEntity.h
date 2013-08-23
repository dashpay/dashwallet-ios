//
//  ZNAddressEntity.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface ZNAddressEntity : NSManagedObject

@property (nonatomic) int32_t txCount;
@property (nonatomic) int64_t balance;
@property (nonatomic, retain) NSString *address;

@end
