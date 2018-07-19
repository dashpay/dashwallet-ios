//
//  DSMasternodeBroadcastHashEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 6/8/18.
//
//

#import "DSMasternodeBroadcastHashEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSMasternodeBroadcastHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSMasternodeBroadcastHashEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *masternodeBroadcastHash;
@property (nullable, nonatomic, retain) DSMasternodeBroadcastEntity *masternodeBroadcast;
@property (nonatomic, assign) uint64_t timestamp;
@property (nonatomic, retain) DSChainEntity * chain;

@end

NS_ASSUME_NONNULL_END
