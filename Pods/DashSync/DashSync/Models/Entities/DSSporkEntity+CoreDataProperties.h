//
//  DSSporkEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 5/28/18.
//
//

#import "DSSporkEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@class DSSporkHashEntity;

@interface DSSporkEntity (CoreDataProperties)

+ (NSFetchRequest<DSSporkEntity *> *)fetchRequest;

@property (nullable,nonatomic,retain) NSData * signature;
@property (nonatomic) int64_t timeSigned;
@property (nonatomic) int64_t value;
@property (nonatomic) int32_t identifier;
@property (nonatomic,retain) DSSporkHashEntity * sporkHash;

@end

NS_ASSUME_NONNULL_END
