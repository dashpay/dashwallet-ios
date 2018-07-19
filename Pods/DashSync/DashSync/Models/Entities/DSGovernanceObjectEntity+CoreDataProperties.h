//
//  DSGovernanceObjectEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 6/14/18.
//
//

#import "DSGovernanceObjectEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@class DSGovernanceVoteHashEntity;

@interface DSGovernanceObjectEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceObjectEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *collateralHash;
@property (nullable, nonatomic, retain) NSData *parentHash;
@property (nullable, nonatomic, retain) NSString *paymentAddress;
@property (nonatomic, assign) uint32_t revision;
@property (nonatomic, assign) uint64_t totalVotesCount;
@property (nullable, nonatomic, retain) NSData *signature;
@property (nullable, nonatomic, retain) NSString * url;
@property (nonatomic, assign) uint64_t startEpoch;
@property (nonatomic, assign) uint64_t endEpoch;
@property (nonatomic, assign) uint64_t timestamp;
@property (nonatomic, assign) uint32_t type;
@property (nullable, nonatomic, retain) DSGovernanceObjectHashEntity *governanceObjectHash;
@property (nullable, nonatomic, retain) NSString * identifier;
@property (nonatomic, assign) uint64_t amount;
@property (nonatomic, retain) NSOrderedSet<DSGovernanceVoteHashEntity *> *voteHashes;

@end

NS_ASSUME_NONNULL_END
