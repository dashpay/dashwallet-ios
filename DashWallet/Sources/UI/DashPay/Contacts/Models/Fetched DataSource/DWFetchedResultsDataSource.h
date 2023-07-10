//
//  Created by Andrew Podkovyrin
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

@protocol DWFetchedResultsDataSourceDelegate <NSObject>

- (void)fetchedResultsDataSourceDidUpdate:(DWFetchedResultsDataSource *)fetchedResultsDataSource;

@end

@interface DWFetchedResultsDataSource : NSObject

@property (nonatomic, assign) BOOL shouldSubscribeToNotifications;

@property (readonly, nonatomic, strong) NSManagedObjectContext *context;
@property (readonly, nonatomic, copy) NSString *entityName;
@property (readonly, nonatomic, strong) NSPredicate *predicate;
@property (nullable, readonly, nonatomic, copy) NSString *sectionNameKeyPath;
@property (nullable, readonly, nonatomic, strong) NSPredicate *invertedPredicate;
@property (nullable, readonly, nonatomic, copy) NSArray<NSSortDescriptor *> *sortDescriptors;

@property (null_resettable, nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property (nullable, nonatomic, strong) id<DWFetchedResultsDataSourceDelegate> delegate;

- (void)start;
- (void)stop;

- (instancetype)initWithContext:(NSManagedObjectContext *)context NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
