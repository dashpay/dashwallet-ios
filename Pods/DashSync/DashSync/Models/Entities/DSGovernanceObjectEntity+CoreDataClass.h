//
//  DSGovernanceObjectEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/14/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "DSGovernanceObject.h"

@class DSChainEntity, DSGovernanceObjectHashEntity;

NS_ASSUME_NONNULL_BEGIN

@interface DSGovernanceObjectEntity : NSManagedObject

- (void)setAttributesFromGovernanceObject:(DSGovernanceObject * _Nonnull)governanceObject forHashEntity:(DSGovernanceObjectHashEntity* _Nullable)hashEntity;
+ (NSUInteger)countForChain:(DSChainEntity* _Nonnull)chain;
- (DSGovernanceObject*)governanceObject;

@end

NS_ASSUME_NONNULL_END

#import "DSGovernanceObjectEntity+CoreDataProperties.h"
