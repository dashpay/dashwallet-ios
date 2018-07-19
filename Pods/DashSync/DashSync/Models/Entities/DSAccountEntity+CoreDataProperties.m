//
//  DSAccountEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/22/18.
//
//

#import "DSAccountEntity+CoreDataProperties.h"

@implementation DSAccountEntity (CoreDataProperties)

+ (NSFetchRequest<DSAccountEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSAccountEntity"];
}

@dynamic index;
@dynamic walletUniqueID;
@dynamic transactionOutputs;
@dynamic derivationPaths;

@end
