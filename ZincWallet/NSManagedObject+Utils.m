//
//  NSManagedObject+Utils.m
//
//  Created by Aaron Voisine on 8/22/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "NSManagedObject+Utils.h"

@implementation NSManagedObject (Utils)

#pragma mark - create objects

+ (instancetype)managedObject
{
    __block NSEntityDescription *entity = nil;
    __block NSManagedObject *obj = nil;
    
    [[self context] performBlockAndWait:^{
        entity = [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:[self context]];
        obj = [[self alloc] initWithEntity:entity insertIntoManagedObjectContext:[self context]];
    }];
    
    return obj;
}

+ (NSArray *)managedObjectArrayWithLength:(NSUInteger)length
{
    __block NSEntityDescription *entity = nil;
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:length];
    
    [[self context] performBlockAndWait:^{
        entity = [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:[self context]];
        
        for (NSUInteger i = 0; i < length; i++) {
            [a addObject:[[self alloc] initWithEntity:entity insertIntoManagedObjectContext:[self context]]];
        }
    }];
    
    return a;
}

#pragma mark - fetch existing objects

+ (NSArray *)allObjects
{
    return [self fetchObjects:[self fetchRequest]];
}

+ (NSArray *)objectsMatching:(NSString *)predicateFormat, ...
{
    NSArray *a;
    va_list args;

    va_start(args, predicateFormat);
    a = [self objectsMatching:predicateFormat arguments:args];
    va_end(args);
    return a;
}

+ (NSArray *)objectsMatching:(NSString *)predicateFormat arguments:(va_list)args
{
    NSFetchRequest *request = [self fetchRequest];
    
    request.predicate = [NSPredicate predicateWithFormat:predicateFormat arguments:args];
    return [self fetchObjects:request];
}

+ (NSArray *)objectsSortedBy:(NSString *)key ascending:(BOOL)ascending
{
    return [self objectsSortedBy:key ascending:ascending offset:0 limit:0];
}

+ (NSArray *)objectsSortedBy:(NSString *)key ascending:(BOOL)ascending offset:(NSUInteger)offset limit:(NSUInteger)limit
{
    NSFetchRequest *request = [self fetchRequest];
    
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:key ascending:ascending]];
    request.fetchOffset = offset;
    request.fetchLimit = limit;
    return [self fetchObjects:request];
}

+ (NSArray *)fetchObjects:(NSFetchRequest *)request
{
    __block NSArray *a = nil;
    __block NSError *error = nil;

    [[self context] performBlockAndWait:^{
        a = [[self context] executeFetchRequest:request error:&error];
        if (! a) NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
    }];
     
    return a;
}

#pragma mark - delete objects

+ (NSUInteger)deleteObjects:(NSArray *)objects
{
    [[self context] performBlockAndWait:^{
        [objects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [[self context] deleteObject:obj];
        }];
    }];
    
    return objects.count;
}

#pragma mark - count exising objects

+ (NSUInteger)countAllObjects
{
    return [self countObjects:[self fetchRequest]];
}

+ (NSUInteger)countObjectsMatching:(NSString *)predicateFormat, ...
{
    NSUInteger count;
    va_list args;
    
    va_start(args, predicateFormat);
    count = [self countObjectsMatching:predicateFormat arguments:args];
    va_end(args);
    return count;
}

+ (NSUInteger)countObjectsMatching:(NSString *)predicateFormat arguments:(va_list)args
{
    NSFetchRequest *request = [self fetchRequest];
    
    request.predicate = [NSPredicate predicateWithFormat:predicateFormat arguments:args];
    return [self countObjects:request];
}

+ (NSUInteger)countObjects:(NSFetchRequest *)request
{
    __block NSUInteger count = 0;
    __block NSError *error = nil;

    [[self context] performBlockAndWait:^{
        count = [[self context] countForFetchRequest:request error:&error];
        if (count == NSNotFound) NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
    }];
    
    return count;
}

#pragma mark - core data stack

// Returns the managed object context for the application. If the context doesn't already exist,
// it is created and bound to the persistent store coordinator for the application.
+ (NSManagedObjectContext *)context
{
    static NSManagedObjectContext *moc = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        NSURL *docURL =
            [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
        NSURL *modelURL = [NSBundle.mainBundle URLsForResourcesWithExtension:@"momd" subdirectory:nil].lastObject;
        NSString *projName = [[modelURL lastPathComponent] stringByDeletingPathExtension];
        NSURL *storeURL = [[docURL URLByAppendingPathComponent:projName] URLByAppendingPathExtension:@"sqlite"];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        NSPersistentStoreCoordinator *coordinator =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        NSError *error = nil;
        
        if ([coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL
             options:@{NSMigratePersistentStoresAutomaticallyOption:@(YES),
                       NSInferMappingModelAutomaticallyOption:@(YES)} error:&error] == nil) {
            NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
#if DEBUG
            abort();
#else
            // if this is a not a debug build, attempt to delete and create a new persisent data store before crashing
            if (! [[NSFileManager defaultManager] removeItemAtURL:storeURL error:&error]) {
                NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
            }
            
            if ([coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL
                 options:@{NSMigratePersistentStoresAutomaticallyOption:@(YES),
                           NSInferMappingModelAutomaticallyOption:@(YES)} error:&error] == nil) {
                NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
                abort(); // Forsooth, I am slain!
            }
#endif
        }

        if (coordinator) {
            moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
            [moc setPersistentStoreCoordinator:coordinator];
            
            // Saves changes in the application's managed object context before the application terminates.
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil
             queue:nil usingBlock:^(NSNotification *note) {
                [self saveContext];
            }];
        }
    });
    
    return moc;
}

+ (void)saveContext
{
    [[self context] performBlock:^{
        NSError *error = nil;

        if ([[self context] hasChanges] && ! [[self context] save:&error]) {
            NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
#if DEBUG
            abort();
#endif
        }
    }];
}

#pragma mark - entity methods

+ (NSString *)entityName
{
    return NSStringFromClass([self class]);
}

+ (NSFetchRequest *)fetchRequest
{
    return [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
}

+ (NSFetchedResultsController *)fetchedResultsController:(NSFetchRequest *)request
{
    __block NSFetchedResultsController *c = nil;

    [[self context] performBlockAndWait:^{
        c = [[NSFetchedResultsController alloc] initWithFetchRequest:request managedObjectContext:[self context]
             sectionNameKeyPath:nil cacheName:nil];
    }];
    
    return c;
}

- (void)deleteObject
{
    [[self managedObjectContext] performBlockAndWait:^{
        [[self managedObjectContext] deleteObject:self];
    }];
}

- (id)get:(NSString *)key
{
    __block id value = nil;
    
    [[self managedObjectContext] performBlockAndWait:^{
        value = [self valueForKey:key];
    }];

    return value;
}

- (void)set:(NSString *)key to:(id)value
{
    [[self managedObjectContext] performBlockAndWait:^{
        [self setValue:value forKey:key];
    }];
}

@end
