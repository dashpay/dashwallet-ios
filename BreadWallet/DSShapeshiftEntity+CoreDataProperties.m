//
//  DSShapeshiftEntity+CoreDataProperties.m
//  BreadWallet
//
//  Created by Sam Westrich on 1/31/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

#import "DSShapeshiftEntity+CoreDataProperties.h"

@implementation DSShapeshiftEntity (CoreDataProperties)

+ (NSFetchRequest<DSShapeshiftEntity *> *)fetchRequest {
	return [[NSFetchRequest alloc] initWithEntityName:@"DSShapeshiftEntity"];
}

@dynamic errorMessage;
@dynamic expiresAt;
@dynamic inputAddress;
@dynamic inputCoinAmount;
@dynamic inputCoinType;
@dynamic isFixedAmount;
@dynamic outputCoinAmount;
@dynamic outputCoinType;
@dynamic outputTransactionId;
@dynamic shapeshiftStatus;
@dynamic withdrawalAddress;

@end
