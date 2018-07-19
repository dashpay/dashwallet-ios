//
//  DSAccountEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/22/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DSTxOutputEntity,DSDerivationPath;

NS_ASSUME_NONNULL_BEGIN

@interface DSAccountEntity : NSManagedObject

+ (DSAccountEntity* _Nonnull)accountEntityForWalletUniqueID:(NSString*)walletUniqueID index:(uint32_t)index;

@end

NS_ASSUME_NONNULL_END

#import "DSAccountEntity+CoreDataProperties.h"
