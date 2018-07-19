//
//  DSGovernanceObjectHashEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 6/14/18.
//
//

#import "DSGovernanceObjectHashEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSGovernanceObjectHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceObjectHashEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *governanceObjectHash;
@property (nonatomic, assign) uint64_t timestamp;
@property (nullable, nonatomic, retain) DSChainEntity *chain;
@property (nullable, nonatomic, retain) DSGovernanceObjectEntity *governanceObject;

@end

NS_ASSUME_NONNULL_END
