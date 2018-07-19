//
//  DSSimplifiedMasternodeEntry.h
//  DashSync
//
//  Created by Sam Westrich on 7/12/18.
//

#import <Foundation/Foundation.h>

@interface DSSimplifiedMasternodeEntry : NSObject

@property(nonatomic,readonly) UInt256 providerRegistrationTransactionHash;
@property(nonatomic,readonly) UInt128 address;
@property(nonatomic,readonly) uint16_t port;
@property(nonatomic,readonly) UInt160 keyIDOperator;
@property(nonatomic,readonly) UInt160 keyIDVoting;
@property(nonatomic,readonly) BOOL isValid;
@property(nonatomic,readonly) UInt256 simplifiedMasternodeEntryHash;

+(instancetype)simplifiedMasternodeEntryWithData:(NSData*)data;

@end
