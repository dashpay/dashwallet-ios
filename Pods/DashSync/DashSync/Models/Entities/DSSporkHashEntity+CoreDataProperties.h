//
//  DSSporkHashEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 7/17/18.
//
//

#import "DSSporkHashEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSSporkHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSSporkHashEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *sporkHash;
@property (nullable, nonatomic, retain) DSChainEntity *chain;
@property (nullable, nonatomic, retain) DSSporkEntity *spork;

@end

NS_ASSUME_NONNULL_END
