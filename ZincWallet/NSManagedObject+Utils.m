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

#pragma mark - Object Creation

+ (instancetype)managedObject
{
    return [[self alloc] initWithEntity:[self entity] insertIntoManagedObjectContext:[self context]];
}

+ (NSArray *)allObjects
{
    NSError *error = nil;
    NSArray *r = [[self context] executeFetchRequest:[self fetchRequest] error:&error];

    if (r) return r;
    NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error, error.userInfo);
    return r;
}

+ (NSArray *)objectsMatching:(NSString *)predicateFormat, ...
{
    NSArray *r = nil;
    va_list args;
    
    va_start(args, predicateFormat);
    r = [self objectsMatching:predicateFormat arguments:args];
    va_end(args);
    return r;
}

+ (NSArray *)objectsMatching:(NSString *)predicateFormat arguments:(va_list)argList
{
    NSError *error = nil;
    NSFetchRequest *req = [self fetchRequest];
    
    req.predicate = [NSPredicate predicateWithFormat:predicateFormat arguments:argList];
    
    NSArray *r = [[self context] executeFetchRequest:req error:&error];
   
    if (r) return r;
    NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error, error.userInfo);
    return r;
}

+ (NSArray *)objectsSortedBy:(NSString *)key ascending:(BOOL)ascending
{
    NSError *error = nil;
    NSFetchRequest *req = [self fetchRequest];
    
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:key ascending:ascending]];
    
    NSArray *r = [[self context] executeFetchRequest:req error:&error];
    
    if (r) return r;
    NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error, error.userInfo);
    return r;    
}

#pragma mark - Core Data stack

// Returns the managed object context for the application. If the context doesn't already exist, it is created and bound
// to the persistent store coordinator for the application.
+ (NSManagedObjectContext *)context
{
    static NSManagedObjectContext *context = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        NSURL *docURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                          inDomains:NSUserDomainMask] lastObject];
        NSURL *modelURL = [NSBundle.mainBundle URLsForResourcesWithExtension:@"momd" subdirectory:nil].lastObject;
        NSString *projName = [[modelURL lastPathComponent] stringByDeletingPathExtension];
        NSURL *storeURL = [[docURL URLByAppendingPathComponent:projName] URLByAppendingPathExtension:@"sqlite"];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc]
                                                     initWithManagedObjectModel:model];
        __block NSError *error = nil;
        
        if (! [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
               error:&error]) {
            NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                  error.userInfo);

#if DEBUG
            abort();
#else
            // if this is a not a debug build, attempt to delete and create a new persisent data store before crashing
            if (! [[NSFileManager defaultManager] removeItemAtURL:storeURL error:&error]) {
                NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                      error.userInfo);
            }
            
            if (! [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil
                   error:&error]) {
                NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                      error.userInfo);
                abort(); // forsooth, I am slain
            }
#endif
        }

        if (coordinator) {
            context = [NSManagedObjectContext new];
            [context setPersistentStoreCoordinator:coordinator];
            
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
    [[self context] performBlock:^{
        NSError *error = nil;

        if ([[self context] hasChanges] && ! [[self context] save:&error]) {
            NSLog(@"[%s %s] line %d: %@, %@", object_getClassName(self), sel_getName(_cmd), __LINE__, error,
                  error.userInfo);
#if DEBUG
            abort();
#endif
        }
    }];
}

#pragma mark - Entity methods

+ (NSString *)entityName
{
    return NSStringFromClass(self);
}

+ (NSEntityDescription *)entity
{
    return [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:[self context]];
}

+ (NSFetchRequest *)fetchRequest
{
    return [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
}

+ (NSFetchedResultsController *)fetchedResultsController {
    return [[NSFetchedResultsController alloc] initWithFetchRequest:[self fetchRequest]
            managedObjectContext:[self context] sectionNameKeyPath:nil cacheName:[self entityName]];
}

- (void)deleteObject
{
    [[self managedObjectContext] deleteObject:self];
}

@end
