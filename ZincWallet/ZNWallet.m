//
//  ZNWallet.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWallet.h"
#import "AFNetworking.h"
#import "NSString+Base58.h"

#define UNSPENT_URL @"http://blockchain.info/unspent?active="
#define ADDRESS_URL @"http://blockchain.info/multiaddr?active="
#define SCRIPT_PREFIX @"76a914" // OP_DUP OP_HASH160 20bytes
#define SCRIPT_SUFFIX @"88ac" // OP_EQUALVERIFY OP_CHECKSIG

@interface ZNWallet ()

@property (nonatomic, strong) NSMutableArray *spentAddresses;
@property (nonatomic, strong) NSMutableArray *fundedAddresses;
@property (nonatomic, strong) NSMutableArray *receiveAddresses;
@property (nonatomic, strong) NSMutableDictionary *unspentOutputs;
@property (nonatomic, strong) NSMutableDictionary *addressBalances;

@end

@implementation ZNWallet

// query blockchain for the given addresses
- (void)queryAddresses:(NSArray *)addresses
{
    if (! addresses.count) return;

    NSURL *url = [NSURL URLWithString:[ADDRESS_URL stringByAppendingString:[addresses componentsJoinedByString:@"|"]]];
    
    [[AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
      success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        [JSON[@"addresses"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *address = obj[@"address"];
            
            if (! address) return;
            
            if ([obj[@"n_tx"] longLongValue] > 0) {
                if ([obj[@"final_balance"] longLongValue] > 0) {
                    [self.fundedAddresses addObject:address];
                }
                else {
                    [self.spentAddresses addObject:address];
                }
            }
            else {
                [self.receiveAddresses addObject:address];
            }
            
            self.addressBalances[address] = obj[@"final_balance"];
        }];
        
        [self queryUnspentOutputs:self.fundedAddresses];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }] start];
}

// query blockchain for unspent outputs of the given addresses
- (void)queryUnspentOutputs:(NSArray *)addresses
{
    if (! addresses.count) return;
    
    NSURL *url = [NSURL URLWithString:[UNSPENT_URL stringByAppendingString:[addresses componentsJoinedByString:@"|"]]];
    
    [[AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
      success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
          [JSON[@"unspent_outputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
              NSString *script = obj[@"script"];
              
              if (! [script hasPrefix:SCRIPT_PREFIX] || ! [script hasSuffix:SCRIPT_SUFFIX]) return;

              NSString *hexAddress =
                  [@"00" stringByAppendingString:[script substringWithRange:NSMakeRange(SCRIPT_PREFIX.length, 40)]];

              self.unspentOutputs[[hexAddress hexToBase58check]] = obj;
          }];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }] start];
}

- (id)init
{
    if (! (self = [super init])) return nil;
    
    [self queryAddresses:@[@"1T7cQHDFLuMVx77cDBn9jKkRQDuasXqt2", @"18WsLH7MjjrGE5LgyZHZVwwdRoSKLunYKk"]];
    
    return self;
}

- (id)initWithSeed:(NSString *)seed
{
    return [self init];
}

- (NSString *)transactionFor:(double)amount to:(NSString *)address
{
    return nil;
}

@end
