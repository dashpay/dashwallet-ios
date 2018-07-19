//
//  DSGovernanceObject.h
//  DashSync
//
//  Created by Sam Westrich on 6/11/18.
//

#import <Foundation/Foundation.h>

#import "IntTypes.h"

@class DSChain,DSPeer,DSGovernanceVote,DSGovernanceObjectEntity,DSTransaction,DSAccount;

typedef NS_ENUM(uint32_t, DSGovernanceObjectType) {
    DSGovernanceObjectType_Uknown = 0,
    DSGovernanceObjectType_Proposal = 1,
    DSGovernanceObjectType_Trigger = 2,
    DSGovernanceObjectType_Watchdog = 3, //deprecated
};

@protocol DSGovernanceObjectDelegate;

@interface DSGovernanceObject : NSObject

@property (nonatomic, readonly) UInt256 collateralHash;
@property (nonatomic, readonly) UInt256 parentHash;
@property (nonatomic, readonly) uint32_t revision;
@property (nonatomic, readonly) NSData *signature;
@property (nonatomic, readonly) NSTimeInterval timestamp;
@property (nonatomic, readonly) DSGovernanceObjectType type;
@property (nonatomic, readonly) UInt256 governanceObjectHash;
@property (nonatomic, readonly) NSString * governanceMessage;
@property (nonatomic, readonly) DSChain * chain;
@property (nonatomic, readonly) NSString * identifier;
@property (nonatomic, readonly) uint64_t amount;
@property (nonatomic, readonly) BOOL finishedSync;
@property (nonatomic, readonly) uint64_t startEpoch;
@property (nonatomic, readonly) uint64_t endEpoch;
@property (nonatomic, readonly) NSString *paymentAddress;
@property (nonatomic, readonly) NSString * url;
@property (nonatomic, readonly) BOOL isValid;
@property (nonatomic, readonly) DSGovernanceObjectEntity * governanceObjectEntity;

@property (nonatomic, readonly) NSUInteger recentGovernanceVoteHashesCount;
@property (nonatomic, readonly) NSUInteger last3HoursStandaloneGovernanceVoteHashesCount;
@property (nonatomic, readonly) NSUInteger governanceVotesCount;

@property (nonatomic, assign) uint64_t totalGovernanceVoteCount;

@property (nonatomic, strong) NSManagedObjectContext * managedObjectContext;

@property (nonatomic, weak) id<DSGovernanceObjectDelegate> delegate;

+(DSGovernanceObject* _Nullable)governanceObjectFromMessage:(NSData * _Nonnull)message onChain:(DSChain* _Nonnull)chain;
-(instancetype)initWithType:(DSGovernanceObjectType)governanceObjectType parentHash:(UInt256)parentHash revision:(uint32_t)revision timestamp:(NSTimeInterval)timestamp signature:(NSData* _Nullable)signature collateralHash:(UInt256)collateralHash governanceObjectHash:(UInt256)governanceObjectHash identifier:(NSString* _Nullable)identifier amount:(uint64_t)amount startEpoch:(uint64_t)startEpoch endEpoch:(uint64_t)endEpoch paymentAddress:(NSString* _Nullable)paymentAddress url:(NSString * _Nullable)url onChain:(DSChain* _Nonnull)chain;

-(void)peer:(DSPeer * _Nullable)peer hasGovernanceVoteHashes:(NSSet* _Nonnull)governanceVoteHashes;
-(void)peer:(DSPeer * _Nullable)peer relayedGovernanceVote:(DSGovernanceVote*  _Nonnull)governanceVote;

-(void)save;

-(DSTransaction* _Nullable)collateralTransactionForAccount:(DSAccount* _Nonnull)account;

-(void)registerCollateralTransaction:(DSTransaction* _Nonnull)transaction;

-(NSData*)dataMessage;

@end

@protocol DSGovernanceObjectDelegate<NSObject>

//we are syncing and a random vote comes in
-(void)governanceObject:(DSGovernanceObject*)governanceObject didReceiveUnknownHashes:(NSSet*)hash fromPeer:(DSPeer*)peer;

@end
