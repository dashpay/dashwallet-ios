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

#import "DWFetchedResultsDataSource.h"

#import <DashSync/DSLogger.h>
#import <DashSync/NSPredicate+DSUtils.h>

static NSUInteger const FETCH_BATCH_SIZE = 20;

NS_ASSUME_NONNULL_BEGIN

@interface DWFetchedResultsDataSource ()

@property (nonatomic, assign) BOOL subscribedToNotifications;

@end

NS_ASSUME_NONNULL_END

@implementation DWFetchedResultsDataSource

- (instancetype)initWithContext:(NSManagedObjectContext *)context
                        entityName:(NSString *)entityName
    shouldSubscribeToNotifications:(BOOL)shouldSubscribeToNotifications {
    self = [super init];
    if (self) {
        _context = context;
        _entityName = entityName;
        _shouldSubscribeToNotifications = shouldSubscribeToNotifications;
    }
    return self;
}

- (void)start {
    NSParameterAssert(self.predicate);
    NSParameterAssert(self.sortDescriptors);
    // invertedPredicate is not mandatory

    if (self.shouldSubscribeToNotifications && !self.subscribedToNotifications) {
        self.subscribedToNotifications = YES;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(backgroundManagedObjectContextDidSaveNotification:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:self.context];
    }

    [self fetchedResultsController];
}

- (void)stop {
    self.fetchedResultsController = nil;

    if (self.shouldSubscribeToNotifications && self.subscribedToNotifications) {
        self.subscribedToNotifications = NO;

        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSManagedObjectContextDidSaveNotification
                                                      object:self.context];
    }
}

- (NSFetchedResultsController *)fetchedResultsController {
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }

    NSManagedObjectContext *context = self.context;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = [NSEntityDescription entityForName:self.entityName inManagedObjectContext:context];
    fetchRequest.fetchBatchSize = FETCH_BATCH_SIZE;
    fetchRequest.sortDescriptors = self.sortDescriptors;
    fetchRequest.predicate = self.predicate;

    NSFetchedResultsController *fetchedResultsController =
        [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                            managedObjectContext:context
                                              sectionNameKeyPath:nil
                                                       cacheName:nil];
    _fetchedResultsController = fetchedResultsController;
    NSError *error = nil;
    if (![fetchedResultsController performFetch:&error]) {
        // Replace this implementation with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        DSLogError(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    return _fetchedResultsController;
}

#pragma mark - Private

- (NSPredicate *)classPredicate {
    return [NSPredicate predicateWithFormat:@"self isKindOfClass: %@", NSClassFromString(self.entityName)];
}

- (NSPredicate *)predicateInContext {
    return [self.predicate predicateInContext:self.context];
}

- (NSPredicate *)invertedPredicateInContext {
    return [self.invertedPredicate predicateInContext:self.context];
}

- (NSPredicate *)fullPredicateInContext {
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[ [self classPredicate], [self predicateInContext] ]];
}

- (NSPredicate *)fullInvertedPredicateInContext {
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[ [self classPredicate], [self invertedPredicateInContext] ]];
}

- (void)backgroundManagedObjectContextDidSaveNotification:(NSNotification *)notification {
    BOOL (^objectsHaveChanged)(NSSet *) = ^BOOL(NSSet *objects) {
        NSSet *foundObjects = [objects filteredSetUsingPredicate:[self fullPredicateInContext]];
        if (foundObjects.count) {
            return YES;
        }
        return NO;
    };

    BOOL (^objectsHaveChangedInverted)(NSSet *) = ^BOOL(NSSet *objects) {
        if (!self.invertedPredicate) {
            return NO;
        }
        NSSet *foundObjects = [objects filteredSetUsingPredicate:[self fullInvertedPredicateInContext]];
        if (foundObjects.count) {
            return YES;
        }
        return NO;
    };


    NSSet<NSManagedObject *> *insertedObjects = notification.userInfo[NSInsertedObjectsKey];
    NSSet<NSManagedObject *> *updatedObjects = notification.userInfo[NSUpdatedObjectsKey];
    NSSet<NSManagedObject *> *deletedObjects = notification.userInfo[NSDeletedObjectsKey];
    BOOL inserted = NO;
    BOOL updated = NO;
    BOOL deleted = NO;
    BOOL insertedInverted = NO;
    BOOL deletedInverted = NO;
    if ((inserted = objectsHaveChanged(insertedObjects)) ||
        (updated = objectsHaveChanged(updatedObjects)) ||
        (deleted = objectsHaveChanged(deletedObjects)) ||
        (insertedInverted = objectsHaveChangedInverted(insertedObjects)) ||
        (deletedInverted = objectsHaveChangedInverted(deletedObjects))) {
        if (inserted || updated || deleted) {
            insertedInverted = objectsHaveChangedInverted(insertedObjects);
            deletedInverted = objectsHaveChangedInverted(deletedObjects);
        }
        [self.context mergeChangesFromContextDidSaveNotification:notification];
        if (insertedInverted || deletedInverted) {
            self.fetchedResultsController = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate fetchedResultsDataSourceDidUpdate:self];
            });
        }
    }
}

@end
