//
//  DSGovernanceSyncManager.h
//  DashSync
//
//  Created by Sam Westrich on 6/12/18.
//

#import <Foundation/Foundation.h>
#import "DSGovernanceObject.h"
#import "DSGovernanceVote.h"

FOUNDATION_EXPORT NSString* _Nonnull const DSGovernanceObjectListDidChangeNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSGovernanceObjectCountUpdateNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSGovernanceVotesDidChangeNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSGovernanceVoteCountUpdateNotification;

#define SUPERBLOCK_AVERAGE_TIME 2575480
#define PROPOSAL_COST 500000000

@class DSPeer,DSChain,DSGovernanceObject,DSGovernanceVote;

@interface DSGovernanceSyncManager : NSObject <DSGovernanceObjectDelegate>

@property (nonatomic,readonly) DSChain * chain;
@property (nonatomic,readonly) NSUInteger recentGovernanceObjectHashesCount;
@property (nonatomic,readonly) NSUInteger last3HoursStandaloneGovernanceObjectHashesCount;
@property (nonatomic,readonly) NSUInteger governanceObjectsCount;
@property (nonatomic,readonly) NSUInteger proposalObjectsCount;

@property (nonatomic,readonly) NSUInteger governanceVotesCount;
@property (nonatomic,readonly) NSUInteger totalGovernanceVotesCount;

@property (nonatomic,readonly) DSGovernanceObject * currentGovernanceSyncObject;


-(instancetype)initWithChain:(DSChain*)chain;

-(void)peer:(DSPeer * _Nullable)peer relayedGovernanceObject:(DSGovernanceObject * _Nonnull)governanceObject;

-(void)peer:(DSPeer * _Nullable)peer relayedGovernanceVote:(DSGovernanceVote*  _Nonnull)governanceVote;

-(void)peer:(DSPeer * _Nullable)peer hasGovernanceObjectHashes:(NSSet* _Nonnull)governanceObjectHashes;

-(void)requestGovernanceObjectsFromPeer:(DSPeer*)peer;

-(void)finishedGovernanceVoteSyncWithPeer:(DSPeer*)peer;

-(void)vote:(DSGovernanceVoteOutcome)governanceVoteOutcome onGovernanceProposal:(DSGovernanceObject* _Nonnull)governanceObject;

-(void)wipeGovernanceInfo;

-(DSGovernanceObject*)createProposalWithIdentifier:(NSString*)identifier toPaymentAddress:(NSString*)paymentAddress forAmount:(uint64_t)amount fromAccount:(DSAccount*)account startDate:(NSDate*)date cycles:(NSUInteger)cycles url:(NSString*)url;


@end
