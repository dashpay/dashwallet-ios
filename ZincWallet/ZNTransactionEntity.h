//
//  ZNTransactionEntity.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class ZNOutputEntity;

@interface ZNTransactionEntity : NSManagedObject

@property (nonatomic, retain) NSData *txHash;
@property (nonatomic) int32_t blockHeight;
@property (nonatomic) NSTimeInterval timeStamp;
@property (nonatomic) int64_t txIndex;
@property (nonatomic, retain) NSOrderedSet *inputs;
@property (nonatomic, retain) NSOrderedSet *outputs;
@end

@interface ZNTransactionEntity (CoreDataGeneratedAccessors)

- (void)insertObject:(ZNOutputEntity *)value inInputsAtIndex:(NSUInteger)idx;
- (void)removeObjectFromInputsAtIndex:(NSUInteger)idx;
- (void)insertInputs:(NSArray *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeInputsAtIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectInInputsAtIndex:(NSUInteger)idx withObject:(ZNOutputEntity *)value;
- (void)replaceInputsAtIndexes:(NSIndexSet *)indexes withInputs:(NSArray *)values;
- (void)addInputsObject:(ZNOutputEntity *)value;
- (void)removeInputsObject:(ZNOutputEntity *)value;
- (void)addInputs:(NSOrderedSet *)values;
- (void)removeInputs:(NSOrderedSet *)values;
- (void)insertObject:(ZNOutputEntity *)value inOutputsAtIndex:(NSUInteger)idx;
- (void)removeObjectFromOutputsAtIndex:(NSUInteger)idx;
- (void)insertOutputs:(NSArray *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeOutputsAtIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectInOutputsAtIndex:(NSUInteger)idx withObject:(ZNOutputEntity *)value;
- (void)replaceOutputsAtIndexes:(NSIndexSet *)indexes withOutputs:(NSArray *)values;
- (void)addOutputsObject:(ZNOutputEntity *)value;
- (void)removeOutputsObject:(ZNOutputEntity *)value;
- (void)addOutputs:(NSOrderedSet *)values;
- (void)removeOutputs:(NSOrderedSet *)values;
@end
