//
//  DSMasternodePing.h
//  DashSync
//
//  Created by Sam Westrich on 5/31/18.
//

#import <Foundation/Foundation.h>
#import "DSChain.h"

@interface DSMasternodePing : NSObject

@property (nonatomic,readonly) DSUTXO utxo;
@property (nonatomic,readonly) UInt256 chaintip;
@property (nonatomic,readonly) NSData * signature;
@property (nonatomic,readonly) NSTimeInterval signatureTimestamp;
@property (nonatomic,readonly) uint64_t packetSize;

+(DSMasternodePing*)masternodePingFromMessage:(NSData *)message;
-(instancetype)initWithUTXO:(DSUTXO)utxo chainTip:(UInt256)chainTip signature:(NSData*)signature signatureTimestamp:(NSTimeInterval)signatureTimestamp;

@end
