//
//  DSMasternodeBroadcastEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/4/18.
//
//

#import "DSMasternodeBroadcastEntity+CoreDataProperties.h"

@implementation DSMasternodeBroadcastEntity (CoreDataProperties)

+ (NSFetchRequest<DSMasternodeBroadcastEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSMasternodeBroadcastEntity"];
}

@dynamic address;
@dynamic masternodeBroadcastHash;
@dynamic port;
@dynamic protocolVersion;
@dynamic signatureTimestamp;
@dynamic utxoHash;
@dynamic utxoIndex;
@dynamic publicKey;
@dynamic signature;
@dynamic uniqueID;
@dynamic claimed;

@end
