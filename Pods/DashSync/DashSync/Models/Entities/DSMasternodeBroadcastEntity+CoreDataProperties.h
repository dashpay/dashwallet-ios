//
//  DSMasternodeBroadcastEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 6/4/18.
//
//

#import "DSMasternodeBroadcastEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSMasternodeBroadcastEntity (CoreDataProperties)

+ (NSFetchRequest<DSMasternodeBroadcastEntity *> *)fetchRequest;

@property (nonatomic, assign) uint32_t address;
@property (nonatomic, retain) DSMasternodeBroadcastHashEntity *masternodeBroadcastHash;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) uint32_t protocolVersion;
@property (nonatomic, assign) uint64_t signatureTimestamp;
@property (nonatomic, assign) uint32_t utxoIndex;
@property (nonatomic, assign) BOOL claimed;
@property (nonnull, nonatomic, retain) NSString *uniqueID;
@property (nullable, nonatomic, retain) NSData *utxoHash;
@property (nullable, nonatomic, retain) NSData *publicKey;
@property (nullable, nonatomic, retain) NSData *signature;

@end

NS_ASSUME_NONNULL_END
