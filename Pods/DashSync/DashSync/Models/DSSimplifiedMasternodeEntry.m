//
//  DSSimplifiedMasternodeEntry.m
//  DashSync
//
//  Created by Sam Westrich on 7/12/18.
//

#import "DSSimplifiedMasternodeEntry.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"

@interface DSSimplifiedMasternodeEntry()

@property(nonatomic,assign) UInt256 providerRegistrationTransactionHash;
@property(nonatomic,assign) UInt256 simplifiedMasternodeEntryHash;
@property(nonatomic,assign) UInt128 address;
@property(nonatomic,assign) uint16_t port;
@property(nonatomic,assign) UInt160 keyIDOperator;
@property(nonatomic,assign) UInt160 keyIDVoting;
@property(nonatomic,assign) BOOL isValid;

@end


@implementation DSSimplifiedMasternodeEntry

-(UInt256)calculateSimplifiedMasternodeEntryHash {
    //hash calculation
    NSMutableData * hashImportantData = [NSMutableData data];
    [hashImportantData appendUInt256:self.providerRegistrationTransactionHash];
    [hashImportantData appendUInt128:self.address];
    [hashImportantData appendUInt32:self.port];
    [hashImportantData appendUInt160:self.keyIDOperator];
    [hashImportantData appendUInt160:self.keyIDVoting];
    [hashImportantData appendUInt8:self.isValid];
    return hashImportantData.SHA256_2;
}

+(instancetype)simplifiedMasternodeEntryWithData:(NSData*)data {
    return [[self alloc] initWithMessage:data];
}

-(instancetype)initWithMessage:(NSData*)message {
    if (!(self = [super init])) return nil;
    NSUInteger length = message.length;
    NSUInteger offset = 0;
    if (length - offset < 32) return nil;
    self.providerRegistrationTransactionHash = [message UInt256AtOffset:offset];
    offset += 32;
    
    if (length - offset < 16) return nil;
    self.address = [message UInt128AtOffset:offset];
    offset += 16;
    
    if (length - offset < 2) return nil;
    self.port = [message UInt16AtOffset:offset];
    offset += 2;
    
    if (length - offset < 20) return nil;
    self.keyIDOperator = [message UInt160AtOffset:offset];
    offset += 20;
    
    if (length - offset < 20) return nil;
    self.keyIDVoting = [message UInt160AtOffset:offset];
    offset += 20;
    
    if (length - offset < 1) return nil;
    self.isValid = [message UInt8AtOffset:offset];
    offset += 1;
    
    self.simplifiedMasternodeEntryHash = [self calculateSimplifiedMasternodeEntryHash];
    
    return self;
}

@end
