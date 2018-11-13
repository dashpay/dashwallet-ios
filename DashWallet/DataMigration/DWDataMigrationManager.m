//
//  DWDataMigrationManager.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 08/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWDataMigrationManager.h"

#import "BRAddressEntity.h"
#import "BRMerkleBlockEntity.h"
#import "BRPeerEntity.h"
#import "BRTransactionEntity.h"
#import "BRTxInputEntity.h"
#import "BRTxMetadataEntity.h"
#import "BRTxOutputEntity.h"

#import <DashSync/DSChainEntity+CoreDataClass.h>
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

static NSUInteger const BatchSize = 100;
static NSString * const OldDataBaseFileName = @"DashWallet.sqlite";

@interface DWDataMigrationManager ()

@property (strong, nonatomic) NSURL *storeURL;
@property (nullable, strong, nonatomic) NSPersistentContainer *persistentContainer;

@end

@implementation DWDataMigrationManager

+ (instancetype)sharedInstance {
    static DWDataMigrationManager *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURL *docURL = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
        _storeURL = [docURL URLByAppendingPathComponent:OldDataBaseFileName];
        _shouldMigrate = [[NSFileManager defaultManager] fileExistsAtPath:_storeURL.path];
    }
    return self;
}

- (void)migrate:(void (^)(BOOL completed))completion {
    __weak __typeof__(self) weakSelf = self;
    [self setupOldStore:^(BOOL readyToMigration) {
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (readyToMigration) {
            [strongSelf performMigration:completion];
        }
        else {
            [strongSelf destroyOldPersistentStore];
            
            if (completion) {
                completion(NO);
            }
        }
    }];
}

#pragma mark Private

- (void)performMigration:(void (^)(BOOL completed))completion {
    __weak __typeof__(self) weakSelf = self;
    [self.persistentContainer performBackgroundTask:^(NSManagedObjectContext *_Nonnull readContext) {
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        BOOL completed = [strongSelf migrateTransactionsFromContext:readContext];
        completed = completed | [strongSelf migrateMerkleBlockFromContext:readContext];
        completed = completed | [strongSelf migratePeerFromContext:readContext];
        completed = completed | [strongSelf migrateAddressFromContext:readContext];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf destroyOldPersistentStore];
            
            if (completion) {
                completion(completed);
            }
        });
    }];
}

- (void)setupOldStore:(void (^)(BOOL readyToMigration))completion {
    if (!self.shouldMigrate) {
        if (completion) {
            completion(NO);
        }

        return;
    }

    // init DSChain on main thread
    [DWEnvironment sharedInstance];

    NSPersistentStoreDescription *storeDescription = [[NSPersistentStoreDescription alloc] initWithURL:self.storeURL];
    self.persistentContainer = [[NSPersistentContainer alloc] initWithName:@"DashWallet"];
    self.persistentContainer.persistentStoreDescriptions = @[ storeDescription ];

    [self.persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *storeDescription, NSError *_Nullable error) {
        NSAssert([NSThread isMainThread], @"Main thread assumed");

        if (completion) {
            completion(error == nil);
        }
    }];
}

- (BOOL)migrateTransactionsFromContext:(NSManagedObjectContext *)readContext {
    NSEntityDescription *entityDescription = [BRTransactionEntity entity];
    NSFetchRequest *fetchRequest = [self.class fetchRequestForEntity:entityDescription.name];
    fetchRequest.relationshipKeyPathsForPrefetching = @[ @"inputs", @"outputs", @"associatedShapeshift" ];

    NSError *error = nil;
    NSArray<BRTransactionEntity *> *objects = [readContext executeFetchRequest:fetchRequest error:&error];
    if (error) {
        return NO;
    }

    DSChainEntity *chain = [DWEnvironment sharedInstance].currentChain.chainEntity;
    NSManagedObjectContext *writeContext = [NSManagedObject context];

    NSUInteger count = 0;
    for (BRTransactionEntity *entity in objects) {
        DSTransactionEntity *transaction = [[DSTransactionEntity alloc] initWithContext:writeContext];
        transaction.lockTime = entity.lockTime;

        NSMutableOrderedSet<DSTxInputEntity *> *inputs = [[NSMutableOrderedSet alloc] init];
        for (BRTxInputEntity *inputEntity in entity.inputs) {
            DSTxInputEntity *input = [[DSTxInputEntity alloc] initWithContext:writeContext];
            input.n = inputEntity.n;
            input.sequence = inputEntity.sequence;
            input.signature = inputEntity.signature;
            input.txHash = inputEntity.txHash;
            [inputs addObject:input];
        }
        [transaction addInputs:inputs];

        NSMutableOrderedSet<DSTxOutputEntity *> *outputs = [[NSMutableOrderedSet alloc] init];
        for (BRTxOutputEntity *outputEntity in entity.outputs) {
            DSTxOutputEntity *output = [[DSTxOutputEntity alloc] initWithContext:writeContext];
            output.address = outputEntity.address;
            output.n = outputEntity.n;
            output.script = outputEntity.script;
            output.shapeshiftOutboundAddress = outputEntity.shapeshiftOutboundAddress;
            output.txHash = outputEntity.txHash;
            output.value = outputEntity.value;
            [outputs addObject:output];
        }
        [transaction addOutputs:outputs];

        if (transaction.associatedShapeshift) {
            DSShapeshiftEntity *shapeshift = [NSEntityDescription insertNewObjectForEntityForName:@"DSShapeshiftEntity" inManagedObjectContext:writeContext];
            shapeshift.errorMessage = [transaction.associatedShapeshift valueForKey:@"errorMessage"];
            shapeshift.expiresAt = [transaction.associatedShapeshift valueForKey:@"expiresAt"];
            shapeshift.inputAddress = [transaction.associatedShapeshift valueForKey:@"inputAddress"];
            shapeshift.inputCoinAmount = [transaction.associatedShapeshift valueForKey:@"inputCoinAmount"];
            shapeshift.inputCoinType = [transaction.associatedShapeshift valueForKey:@"inputCoinType"];
            shapeshift.isFixedAmount = [transaction.associatedShapeshift valueForKey:@"isFixedAmount"];
            shapeshift.outputCoinAmount = [transaction.associatedShapeshift valueForKey:@"outputCoinAmount"];
            shapeshift.outputCoinType = [transaction.associatedShapeshift valueForKey:@"outputCoinType"];
            shapeshift.outputTransactionId = [transaction.associatedShapeshift valueForKey:@"outputTransactionId"];
            shapeshift.shapeshiftStatus = [transaction.associatedShapeshift valueForKey:@"shapeshiftStatus"];
            shapeshift.withdrawalAddress = [transaction.associatedShapeshift valueForKey:@"withdrawalAddress"];
            transaction.associatedShapeshift = shapeshift;
        }

        DSTransactionHashEntity *transactionHash = [[DSTransactionHashEntity alloc] initWithContext:writeContext];
        transactionHash.blockHeight = entity.blockHeight;
        transactionHash.timestamp = entity.timestamp + NSTimeIntervalSince1970;
        transactionHash.txHash = entity.txHash;
        transaction.transactionHash = transactionHash;

        [chain addTransactionHashesObject:transactionHash];

        count++;
        if (count % BatchSize == 0) {
            [DSTransactionEntity saveContext];
        }
    }

    [DSTransactionEntity saveContext];

    return YES;
}

- (BOOL)migrateMerkleBlockFromContext:(NSManagedObjectContext *)readContext {
    NSEntityDescription *entityDescription = [BRMerkleBlockEntity entity];
    NSFetchRequest *fetchRequest = [self.class fetchRequestForEntity:entityDescription.name];

    NSError *error = nil;
    NSArray<BRMerkleBlockEntity *> *objects = [readContext executeFetchRequest:fetchRequest error:&error];
    if (error) {
        return NO;
    }

    DSChainEntity *chain = [DWEnvironment sharedInstance].currentChain.chainEntity;
    NSManagedObjectContext *writeContext = [NSManagedObject context];

    NSUInteger count = 0;
    for (BRMerkleBlockEntity *merkleBlock in objects) {
        DSMerkleBlockEntity *entity = [[DSMerkleBlockEntity alloc] initWithContext:writeContext];
        entity.blockHash = merkleBlock.blockHash;
        entity.flags = merkleBlock.flags;
        entity.hashes = merkleBlock.hashes;
        entity.height = merkleBlock.height;
        entity.merkleRoot = merkleBlock.merkleRoot;
        entity.nonce = merkleBlock.nonce;
        entity.prevBlock = merkleBlock.prevBlock;
        entity.target = merkleBlock.target;
        entity.timestamp = merkleBlock.timestamp + NSTimeIntervalSince1970;
        entity.totalTransactions = merkleBlock.totalTransactions;
        entity.version = merkleBlock.version;

        [chain addBlocksObject:entity];

        count++;
        if (count % BatchSize == 0) {
            [DSTransactionEntity saveContext];
        }
    }

    [DSTransactionEntity saveContext];

    return YES;
}

- (BOOL)migratePeerFromContext:(NSManagedObjectContext *)readContext {
    NSEntityDescription *entityDescription = [BRPeerEntity entity];
    NSFetchRequest *fetchRequest = [self.class fetchRequestForEntity:entityDescription.name];

    NSError *error = nil;
    NSArray<BRPeerEntity *> *objects = [readContext executeFetchRequest:fetchRequest error:&error];
    if (error) {
        return NO;
    }

    DSChainEntity *chain = [DWEnvironment sharedInstance].currentChain.chainEntity;
    NSManagedObjectContext *writeContext = [NSManagedObject context];

    NSUInteger count = 0;
    for (BRPeerEntity *peer in objects) {
        DSPeerEntity *entity = [[DSPeerEntity alloc] initWithContext:writeContext];
        entity.address = peer.address;
        entity.misbehavin = peer.misbehavin;
        entity.port = peer.port;
        entity.services = peer.services;
        entity.timestamp = peer.timestamp + NSTimeIntervalSince1970;

        [chain addPeersObject:entity];

        count++;
        if (count % BatchSize == 0) {
            [DSTransactionEntity saveContext];
        }
    }

    [DSTransactionEntity saveContext];

    return YES;
}

- (BOOL)migrateAddressFromContext:(NSManagedObjectContext *)readContext {
    NSEntityDescription *entityDescription = [BRAddressEntity entity];
    NSFetchRequest *fetchRequest = [self.class fetchRequestForEntity:entityDescription.name];

    NSError *error = nil;
    NSArray<BRAddressEntity *> *objects = [readContext executeFetchRequest:fetchRequest error:&error];
    if (error) {
        return NO;
    }

    NSManagedObjectContext *writeContext = [NSManagedObject context];

    NSUInteger count = 0;
    for (BRAddressEntity *address in objects) {
        DSAddressEntity *entity = [[DSAddressEntity alloc] initWithContext:writeContext];
        entity.address = address.address;
        entity.index = address.index;
        entity.internal = address.internal;
        entity.standalone = YES;

        count++;
        if (count % BatchSize == 0) {
            [DSTransactionEntity saveContext];
        }
    }

    [DSTransactionEntity saveContext];

    return YES;
}

- (void)destroyOldPersistentStore {
    self.persistentContainer = nil;
    
    NSURL *docURL = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL *storeShmURL = [docURL URLByAppendingPathComponent:[OldDataBaseFileName stringByAppendingString:@"-shm"]];
    NSURL *storeWalURL = [docURL URLByAppendingPathComponent:[OldDataBaseFileName stringByAppendingString:@"-wal"]];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtURL:self.storeURL error:nil];
    [fileManager removeItemAtURL:storeShmURL error:nil];
    [fileManager removeItemAtURL:storeWalURL error:nil];
}

+ (NSFetchRequest *)fetchRequestForEntity:(NSString *)name {
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:name];
    fetchRequest.returnsObjectsAsFaults = NO;
    fetchRequest.fetchBatchSize = BatchSize;
    return fetchRequest;
}

@end

NS_ASSUME_NONNULL_END
