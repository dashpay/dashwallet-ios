//
//  DSShapeshiftManager.m
//  DashWallet
//
//  Created by Quantum Explorer on 7/14/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "DSShapeshiftManager.h"
#import <CoreData/CoreData.h>
#import "NSManagedObject+Sugar.h"
#import "DSShapeshiftEntity+CoreDataClass.h"
#import "BRTransactionEntity.h"
#import "BRTxOutputEntity.h"

#define SHAPESHIFT_PUBLIC_KEY @"9bcdf9343a4548c6268e1ee99e6bb43af95e88eb532f4e807b423adb7a96e54664b9c3d1130f3386c005b353402c9e7698236d1e21807b8b87d64dc605552f4a"

@interface DSShapeshiftManager() <NSFetchedResultsControllerDelegate>

@property (nonatomic,strong) NSFetchedResultsController * shapeshiftFetchedResultsController;

@end


@implementation DSShapeshiftManager

-(id)init {
    self = [super init];
    if (self) {
        [self shapeshiftFetchedResultsController];
        [self queryInitialShapeshiftsNeedingInfo];
    }
    return self;
}

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });
    
    return singleton;
}

- (NSData *)httpBodyForParamsDictionary:(NSDictionary *)paramDictionary
{
    NSMutableArray *parameterArray = [NSMutableArray array];
    
    [paramDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSString class]]) {
            NSString *param = [NSString stringWithFormat:@"%@=%@", key, [obj stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
            [parameterArray addObject:param];
        } else {
            NSString *param = [NSString stringWithFormat:@"%@=%@", key, obj];
            [parameterArray addObject:param];
        }
    }];
    
    NSString *string = [parameterArray componentsJoinedByString:@"&"];
    
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Automation KVO

-(NSManagedObjectContext*)managedObjectContext {
    return [NSManagedObject context];
}

-(NSPredicate*)shapeshiftsNeedingInfo {
    // Get all shapeshifts that have been received by shapeshift.io or all shapeshifts that have no deposits but where we can verify a transaction has been pushed on the blockchain
    return [NSPredicate predicateWithFormat:@"(shapeshiftStatus == %@) || ((shapeshiftStatus == %@) && (SUBQUERY(transaction.outputs, $output, ($output.shapeshiftOutboundAddress != NIL)).@count == 1))",@(eShapeshiftAddressStatus_Received),@(eShapeshiftAddressStatus_NoDeposits)];
}

- (NSFetchedResultsController *)fetchedResultsController
{
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // Edit the entity name as appropriate.
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"DSShapeshiftEntity" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    // Set the batch size to a suitable number.
    [fetchRequest setFetchBatchSize:12];
    
    // Edit the sort key as appropriate.
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"expiresAt" ascending:NO];
    NSArray *sortDescriptors = @[sortDescriptor];
    
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    NSPredicate *filterPredicate = [self shapeshiftsNeedingInfo];
    [fetchRequest setPredicate:filterPredicate];
    
    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.managedObjectContext sectionNameKeyPath:nil cacheName:nil];
    aFetchedResultsController.delegate = self;
    NSError *error = nil;
    if (![aFetchedResultsController performFetch:&error]) {
        // Replace this implementation with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    
    return aFetchedResultsController;
}

-(NSFetchedResultsController*)shapeshiftFetchedResultsController {
    
    if (_shapeshiftFetchedResultsController != nil)
    {
        return _shapeshiftFetchedResultsController;
    }
    _shapeshiftFetchedResultsController = [self fetchedResultsController];
    return _shapeshiftFetchedResultsController;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)changeType
      newIndexPath:(NSIndexPath *)newIndexPath {
    if (changeType == NSFetchedResultsChangeInsert) {
        [(DSShapeshiftEntity*)anObject routinelyCheckStatusAtInterval:10];
        NSLog(@"BLOP %@",anObject);
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    
    
}

#pragma mark - Shapeshift Helper calls

-(void)queryInitialShapeshiftsNeedingInfo {
    for (DSShapeshiftEntity * shapeshift in self.shapeshiftFetchedResultsController.fetchedObjects) {
//        for (BRTxOutputEntity * output in  shapeshift.transaction.outputs) {
//            NSLog(@"o %@", output.shapeshiftOutboundAddress);
//        }
        [shapeshift routinelyCheckStatusAtInterval:10];
    }
}

#pragma mark - Shapeshift API calls

////////////////////////////////////////////////////////////////////
/*
 url: shapeshift.io/marketinfo/dash_btc
 method: GET
 
 Success Output:
 {
 "pair"     : "dash_btc",
 "rate"     : 130.12345678,
 "limit"    : 1.2345,
 "min"      : 0.02621232,
 "minerFee" : 0.0001
 }
 */
////////////////////////////////////////////////////////////////////

-(void)GET_marketInfo:(void (^)(NSDictionary *marketInfo, NSError *error))completionBlock {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://shapeshift.io/marketinfo/dash_btc"]
                                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
        if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
            NSError * returnError = connectionError;
            if (!returnError) {
                returnError = [NSError errorWithDomain:@"DashWallet" code:((NSHTTPURLResponse*)response).statusCode userInfo:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(nil,returnError);
            });
            return;
        }
        NSError *error = nil;
        NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(nil,error);
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            
            self.lastMarketInfoCheck = [NSDate date];
            self.rate = [dictionary[@"rate"] doubleValue];
            if (dictionary[@"limit"])
                self.limit = [[[NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%@",dictionary[@"limit"]]] decimalNumberByMultiplyingByPowerOf10:8]
                              unsignedLongLongValue];
            if (dictionary[@"minimum"])
                self.min = [[[NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%@",dictionary[@"minimum"]]] decimalNumberByMultiplyingByPowerOf10:8]
                            unsignedLongLongValue];
            completionBlock(dictionary,nil);
        });
    }] resume];
}

////////////////////////////////////////////////////////////////////
/*
 url: shapeshift.io/txStat/[address]
 method: GET
  
 [address] is the deposit address to look up.
  
 Success Output:  (various depending on status)
  
 Status: No Deposits Received
     {
         status:"no_deposits",
         address:[address]           //matches address submitted
     }
  
 Status: Received (we see a new deposit but have not finished processing it)
     {
         status:"received",
         address:[address]           //matches address submitted
     }
  
 Status: Complete
 {
     status : "complete",
     address: [address],
     withdraw: [withdrawal address],
     incomingCoin: [amount deposited],
     incomingType: [coin type of deposit],
     outgoingCoin: [amount sent to withdrawal address],
     outgoingType: [coin type of withdrawal],
     transaction: [transaction id of coin sent to withdrawal address]
 }
  
 Status: Failed
 {
     status : "failed",
     error: [Text describing failure]
 }
 */
////////////////////////////////////////////////////////////////////

-(void)GET_transactionStatusWithAddress:(NSString*)withdrawalAddress completionBlock:(void (^)(NSDictionary *transactionInfo, NSError *error))completionBlock {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://shapeshift.io/txStat/%@",withdrawalAddress]]
                                             cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                               if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
                                   NSError * returnError = connectionError;
                                   if (!returnError) {
                                       returnError = [NSError errorWithDomain:@"DashWallet" code:((NSHTTPURLResponse*)response).statusCode userInfo:nil];
                                   }
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,returnError);
                                   });
                                   return ;
                               }
                               NSError *error = nil;
                               NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               if (error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,error);
                                   });
                                   return;
                               }
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   completionBlock(dictionary,nil);
                               });
                           }] resume];
}

#pragma mark - POST requests

////////////////////////////////////////////////////////////////////
/*
 url:  shapeshift.io/shift
 method: POST
 data type: JSON
 data required:
 withdrawal     = the address for resulting coin to be sent to
 pair       = what coins are being exchanged in the form [input coin]_[output coin]  ie btc_ltc
 returnAddress  = (Optional) address to return deposit to if anything goes wrong with exchange
 destTag    = (Optional) Destination tag that you want appended to a Ripple payment to you
 rsAddress  = (Optional) For new NXT accounts to be funded, you supply this on NXT payment to you
 apiKey     = (Optional) Your affiliate PUBLIC KEY, for volume tracking, affiliate payments, split-shifts, etc...
 
 example data: {"withdrawal":"AAAAAAAAAAAAA", "pair":"btc_ltc", returnAddress:"BBBBBBBBBBB"}
 
 Success Output:
 {
 deposit: [Deposit Address (or memo field if input coin is BTS / BITUSD)],
 depositType: [Deposit Type (input coin symbol)],
 withdrawal: [Withdrawal Address], //-- will match address submitted in post
 withdrawalType: [Withdrawal Type (output coin symbol)],
 public: [NXT RS-Address pubkey (if input coin is NXT)],
 xrpDestTag : [xrpDestTag (if input coin is XRP)],
 apiPubKey: [public API attached to this shift, if one was given]
 }
 */
////////////////////////////////////////////////////////////////////

-(void)POST_ShiftWithAddress:(NSString*)withdrawalAddress returnAddress:(NSString*)returnAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock {
    NSDictionary *params = @{@"withdrawal": withdrawalAddress, @"pair": @"dash_btc", @"returnAddress":returnAddress,@"apiKey":SHAPESHIFT_PUBLIC_KEY};
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://shapeshift.io/shift"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[self httpBodyForParamsDictionary:params]];
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                               if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
                                   NSError * returnError = connectionError;
                                   if (!returnError) {
                                       returnError = [NSError errorWithDomain:@"DashWallet" code:((NSHTTPURLResponse*)response).statusCode userInfo:nil];
                                   }
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,returnError);
                                   });
                                   return;
                               }
                               NSError *error = nil;
                               NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               if (error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,error);
                                   });
                                   return;
                               }
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   if ([dictionary objectForKey:@"error"]) {
                                       completionBlock(nil,[NSError errorWithDomain:@"DashWallet" code:500 userInfo:@{NSLocalizedDescriptionKey:[dictionary objectForKey:@"error"]
                                                                                                                      }]);
                                   } else {
                                       completionBlock(dictionary,nil);
                                   }
                               });

                           }] resume];
}

////////////////////////////////////////////////////////////////////
/*
 url:  shapeshift.io/mail
 method: POST
 data type: JSON
 data required:
 email    = the address for receipt email to be sent to
 txid       = the transaction id of the transaction TO the user (ie the txid for the withdrawal NOT the deposit)
 
 Success Output:
 {"email":
 {
 "status":"success",
 "message":"Email receipt sent"
 }
 }
 */
////////////////////////////////////////////////////////////////////

-(void)POST_RequestEmailReceiptOfShapeshiftWithOutputTransactionId:(NSString*)shapeshiftOutputTransactionId toEmailAddress:(NSString*)validEmailAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock {
    NSDictionary *params = @{@"email":validEmailAddress,@"txid": shapeshiftOutputTransactionId};
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://shapeshift.io/mail"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[self httpBodyForParamsDictionary:params]];
    NSString * s = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                               if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
                                   NSError * returnError = connectionError;
                                   if (!returnError) {
                                       returnError = [NSError errorWithDomain:@"Shapeshift" code:((NSHTTPURLResponse*)response).statusCode userInfo:nil];
                                   }
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,returnError);
                                   });
                               }
                               NSError *error = nil;
                               NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               if (error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,error);
                                   });
                                   return;
                               }
                               if (dictionary[@"error"]) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,[NSError errorWithDomain:@"Shapeshift" code:416 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                                          dictionary[@"error"]
                                                                                                                      }]);
                                   });
                                   return;
                               }
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   completionBlock(dictionary[@"success"],nil);
                               });
                               
                           }] resume];
    
}


////////////////////////////////////////////////////////////////////
/*
 url: shapeshift.io/sendamount
 method: POST
 data type: JSON
 
 //1. Send amount request
 
 
 Data required:
 
 amount          = the amount to be sent to the withdrawal address
 withdrawal      = the address for coin to be sent to
 pair            = what coins are being exchanged in the form [input coin]_[output coin]  ie ltc_btc
 returnAddress   = (Optional) address to return deposit to if anything goes wrong with exchange
 destTag         = (Optional) Destination tag that you want appended to a Ripple payment to you
 rsAddress       = (Optional) For new NXT accounts to be funded, supply this on NXT payment to you
 apiKey          = (Optional) Your affiliate PUBLIC KEY, for volume tracking, affiliate payments, split-shifts, etc...
 
 example data {"amount":123, "withdrawal":"123ABC", "pair":"ltc_btc", returnAddress:"BBBBBBB"}
 
 
 Success Output:
 
 
 {
 success:
 {
 pair: [pair],
 withdrawal: [Withdrawal Address], //-- will match address submitted in post
 withdrawalAmount: [Withdrawal Amount], // Amount of the output coin you will receive
 deposit: [Deposit Address (or memo field if input coin is BTS / BITUSD)],
 depositAmount: [Deposit Amount], // Exact amount of input coin to send in
 expiration: [timestamp when this will expire],
 quotedRate: [the exchange rate to be honored]
 apiPubKey: [public API attached to this shift, if one was given]
 }
 }
 
 */
////////////////////////////////////////////////////////////////////

-(void)POST_SendAmount:(NSNumber*)amount withAddress:(NSString*)withdrawalAddress returnAddress:(NSString*)returnAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock {
    NSDictionary *params = @{@"amount":amount,@"withdrawal": withdrawalAddress, @"pair": @"dash_btc", @"returnAddress":returnAddress,@"apiKey":SHAPESHIFT_PUBLIC_KEY};
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://shapeshift.io/sendamount"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[self httpBodyForParamsDictionary:params]];
    NSString * s = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                               if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError || !data) {
                                   NSError * returnError = connectionError;
                                   if (!returnError) {
                                       returnError = [NSError errorWithDomain:@"Shapeshift" code:((NSHTTPURLResponse*)response).statusCode userInfo:nil];
                                   }
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,returnError);
                                   });
                               }
                               NSError *error = nil;
                               NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               if (error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,error);
                                   });
                                   return;
                               }
                               if (dictionary[@"error"]) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,[NSError errorWithDomain:@"Shapeshift" code:416 userInfo:@{NSLocalizedDescriptionKey:
                                                                                                                                                                dictionary[@"error"]
                                                                                                                                                            }]);
                                   });
                                   return;
                               }
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   completionBlock(dictionary[@"success"],nil);
                               });
                               
                           }] resume];
}

////////////////////////////////////////////////////////////////////
/*
 url: shapeshift.io/cancelpending
 method: POST
 data type: JSON
 data required: address  = The deposit address associated with the pending transaction
 
 Example data : {address : "1HB5XMLmzFVj8ALj6mfBsbifRoD4miY36v"}
 
 Success Output:
 
 {  success  : " Pending Transaction cancelled "  }
 
 Error Output:
 
 {  error  : {errorMessage}  }
 */
////////////////////////////////////////////////////////////////////

-(void)POST_CancelShiftToAddress:(NSString*)withdrawalAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock {
    NSDictionary *params = @{@"address": withdrawalAddress};
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://shapeshift.io/shift"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[self httpBodyForParamsDictionary:params]];
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                               if (((((NSHTTPURLResponse*)response).statusCode /100) != 2) || connectionError) {
                                   NSError * returnError = connectionError;
                                   if (!returnError) {
                                       returnError = [NSError errorWithDomain:@"DashWallet" code:((NSHTTPURLResponse*)response).statusCode userInfo:nil];
                                   }
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,returnError);
                                   });
                                   return;
                               }
                               NSError *error = nil;
                               NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               if (error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       completionBlock(nil,error);
                                   });
                                   return;
                               }
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   if ([dictionary objectForKey:@"error"]) {
                                       completionBlock(nil,[NSError errorWithDomain:@"DashWallet" code:500 userInfo:@{NSLocalizedDescriptionKey:[dictionary objectForKey:@"error"]
                                                                                                                      }]);
                                   } else {
                                       completionBlock(dictionary,nil);
                                   }
                               });
                               
                           }] resume];
}



@end
