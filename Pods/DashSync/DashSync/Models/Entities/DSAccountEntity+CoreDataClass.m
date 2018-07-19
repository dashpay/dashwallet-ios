//
//  DSAccountEntity+CoreDataClass.m
//  DashSync
//
//  Created by Sam Westrich on 6/22/18.
//
//

#import "DSAccountEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"

@implementation DSAccountEntity

+ (DSAccountEntity* _Nonnull)accountEntityForWalletUniqueID:(NSString*)walletUniqueID index:(uint32_t)index {
    
    NSArray * accounts = [DSAccountEntity objectsMatching:@"walletUniqueID = %@ && index = %@",walletUniqueID,@(index)];
    if ([accounts count]) {
        NSAssert([accounts count] == 1, @"There can only be one account per index per wallet");
        return [accounts objectAtIndex:0];
    }
    DSAccountEntity * accountEntity = [DSAccountEntity managedObject];
    accountEntity.walletUniqueID = walletUniqueID;
    accountEntity.index = index;
    return accountEntity;
}

@end
