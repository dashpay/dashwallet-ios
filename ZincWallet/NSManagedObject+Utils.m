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

#pragma mark - create object

+ (instancetype)managedObject
{
    @synchronized([self context]) {
        return [[self alloc] initWithEntity:[NSEntityDescription entityForName:[self entityName]
                inManagedObjectContext:[self context]] insertIntoManagedObjectContext:[self context]];
    }
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
    NSFetchRequest *req = [self fetchRequest];
    
    req.predicate = [NSPredicate predicateWithFormat:predicateFormat arguments:args];
    return [self fetchObjects:req];
}

+ (NSArray *)objectsSortedBy:(NSString *)key ascending:(BOOL)asc
{
    return [self objectsSortedBy:key ascending:asc offset:0 limit:0];
}

+ (NSArray *)objectsSortedBy:(NSString *)key ascending:(BOOL)asc offset:(NSUInteger)off limit:(NSUInteger)lim
{
    NSFetchRequest *req = [self fetchRequest];
    
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:key ascending:asc]];
    req.fetchOffset = off;
    req.fetchLimit = lim;
    
    return [self fetchObjects:req];
}

+ (NSArray *)fetchObjects:(NSFetchRequest *)req
{
    @synchronized([self context]) {
        NSError *err = nil;
        NSArray *a = [[self context] executeFetchRequest:req error:&err];

        if (! a) NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, err);
        return a;
    }
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
    NSFetchRequest *req = [self fetchRequest];
    
    req.predicate = [NSPredicate predicateWithFormat:predicateFormat arguments:args];
    return [self countObjects:req];
}

+ (NSUInteger)countObjectsSortedBy:(NSString *)key ascending:(BOOL)asc
{
    return [self countObjectsSortedBy:key ascending:asc offset:0 limit:0];
}

+ (NSUInteger)countObjectsSortedBy:(NSString *)key ascending:(BOOL)asc offset:(NSUInteger)off limit:(NSUInteger)lim
{
    NSFetchRequest *req = [self fetchRequest];
    
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:key ascending:asc]];
    req.fetchOffset = off;
    req.fetchLimit = lim;
    
    return [self countObjects:req];
}

+ (NSUInteger)countObjects:(NSFetchRequest *)req
{
    @synchronized([self context]) {
        NSError *err = nil;
        NSUInteger count = [[self context] countForFetchRequest:req error:&err];
        
        if (count == NSNotFound) NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, err);
        return count;
    }    
}

#pragma mark - core data stack

// Returns the managed object context for the application. If the context doesn't already exist,
// it is created and bound to the persistent store coordinator for the application.
+ (NSManagedObjectContext *)context
{
    static NSManagedObjectContext *context = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        NSURL *docURL =
            [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
        NSURL *modelURL = [NSBundle.mainBundle URLsForResourcesWithExtension:@"momd" subdirectory:nil].lastObject;
        NSString *projName = [[modelURL lastPathComponent] stringByDeletingPathExtension];
        NSURL *storeURL = [[docURL URLByAppendingPathComponent:projName] URLByAppendingPathExtension:@"sqlite"];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        NSPersistentStoreCoordinator *coord = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        NSError *err = nil;
        
        if (! [coord addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
               error:&err]) {
            NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, err);
#if DEBUG
            abort();
#else
            // if this is a not a debug build, attempt to delete and create a new persisent data store before crashing
            if (! [[NSFileManager defaultManager] removeItemAtURL:storeURL error:&err]) {
                NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, err);
            }
            
            if (! [coord addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
                   error:&err]) {
                NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, err);
                abort(); // Forsooth, I am slain!
            }
#endif
        }

        if (coord) {
            context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
            [context setPersistentStoreCoordinator:coord];
            
            // Saves changes in the application's managed object context before the application terminates.
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil
             queue:nil usingBlock:^(NSNotification *note) {
                [self saveContext];
            }];
        }
    });
    
    return context;
}

+ (void)saveContext
{
    @synchronized([self context]) {
        NSError *error = nil;

        if ([[self context] hasChanges] && ! [[self context] save:&error]) {
            NSLog(@"%s:%d %s: %@", __FILE__, __LINE__, __FUNCTION__, error);
#if DEBUG
            abort();
#endif
        }
    }
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

+ (NSFetchedResultsController *)fetchedResultsControllerWithFetchRequest:(NSFetchRequest *)req
{
    @synchronized([self context]) {
        return [[NSFetchedResultsController alloc] initWithFetchRequest:req managedObjectContext:[self context]
                sectionNameKeyPath:nil cacheName:req.entityName];
    }
}

- (void)deleteObject
{
    @synchronized([self managedObjectContext]) {
        [[self managedObjectContext] deleteObject:self];
    }
}

@end
