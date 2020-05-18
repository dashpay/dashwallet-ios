//
//  Created by administrator
//  Copyright © 2020 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DWFetchedResultsDataSource;

@interface DWFetchedResultsDataSourceDiffUpdate : NSObject

@property (readonly, nonatomic, copy) NSArray<NSIndexPath *> *inserts;
@property (readonly, nonatomic, copy) NSArray<NSIndexPath *> *deletes;
@property (readonly, nonatomic, copy) NSArray<NSIndexPath *> *updates;
@property (readonly, nonatomic, copy) NSArray<NSArray<NSIndexPath *> *> *moves;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@protocol DWFetchedResultsDataSourceDelegate <NSObject>

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource;
- (void)fetchedResultsDataSource:(DWFetchedResultsDataSource *)fetchedResultsDataSource
                   didDiffUpdate:(DWFetchedResultsDataSourceDiffUpdate *)diffUpdate;

@end

@interface DWFetchedResultsDataSource : NSObject <NSFetchedResultsControllerDelegate>

@property (readonly, nonatomic, strong) NSManagedObjectContext *context;
@property (readonly, nonatomic, copy) NSString *entityName;
@property (readonly, nonatomic, assign) BOOL shouldSubscribeToNotifications;

@property (nullable, nonatomic, strong) NSPredicate *predicate;
@property (nullable, nonatomic, strong) NSPredicate *invertedPredicate;
@property (nullable, nonatomic, copy) NSArray<NSSortDescriptor *> *sortDescriptors;

@property (null_resettable, nonatomic, copy) NSIndexPath * (^indexPathTransformation)(NSIndexPath *indexPath);

@property (null_resettable, nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property (nullable, nonatomic, strong) id<DWFetchedResultsDataSourceDelegate> delegate;

- (void)start;
- (void)stop;

- (instancetype)initWithContext:(NSManagedObjectContext *)context
                        entityName:(NSString *)entityName
    shouldSubscribeToNotifications:(BOOL)shouldSubscribeToNotifications;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
