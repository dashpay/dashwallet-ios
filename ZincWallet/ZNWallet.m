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

#define SCRIPT_SUFFIX @"88ac" // OP_EQUALVERIFY OP_CHECKSIG

#define FUNDED_ADDRESSES_KEY @"FUNDED_ADDRESSES"
#define SPENT_ADDRESSES_KEY @"SPENT_ADDRESSES"
#define RECEIVE_ADDRESSES_KEY @"RECEIVE_ADDRESSES"
#define ADDRESS_BALANCES_KEY @"ADDRESS_BALANCES"
#define UNSPENT_OUTPUTS_KEY @"UNSPENT_OUTPUTS"

@interface ZNWallet ()

@property (nonatomic, strong) NSUserDefaults *defs;
@property (nonatomic, strong) NSMutableArray *spentAddresses;
@property (nonatomic, strong) NSMutableArray *fundedAddresses;
@property (nonatomic, strong) NSMutableArray *receiveAddresses;
@property (nonatomic, strong) NSMutableDictionary *unspentOutputs;
@property (nonatomic, strong) NSMutableDictionary *addressBalances;

@end

@implementation ZNWallet

+ (ZNWallet *)singleton
{
    static ZNWallet *singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [[ZNWallet alloc] init];
    });

    return singleton;
}

// query blockchain for the given addresses
- (void)queryAddresses:(NSArray *)addresses
{
    if (! addresses.count) return;

    NSURL *url = [NSURL URLWithString:[ADDRESS_URL stringByAppendingString:[[addresses componentsJoinedByString:@"|"]
                  stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    
    [[AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        [JSON[@"addresses"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *address = obj[@"address"];
            
            if (! address) return;

            [self.fundedAddresses removeObject:address];
            [self.spentAddresses removeObject:address];
            [self.receiveAddresses removeObject:address];

            self.addressBalances[address] = obj[@"final_balance"];
            
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
        }];
        
        [_defs setObject:self.fundedAddresses forKey:FUNDED_ADDRESSES_KEY];
        [_defs setObject:self.spentAddresses forKey:SPENT_ADDRESSES_KEY];
        [_defs setObject:self.receiveAddresses forKey:RECEIVE_ADDRESSES_KEY];
        [_defs setObject:self.addressBalances forKey:ADDRESS_BALANCES_KEY];
        
        [self queryUnspentOutputs:self.fundedAddresses];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }] start];
}

// query blockchain for unspent outputs of the given addresses
- (void)queryUnspentOutputs:(NSArray *)addresses
{
    if (! addresses.count) return;
    
    NSURL *url = [NSURL URLWithString:[UNSPENT_URL stringByAppendingString:[[addresses componentsJoinedByString:@"|"]
                  stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    
    [[AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        //XXX verify response success before clearing out previous unspent outputs
        [self.unspentOutputs removeObjectsForKeys:addresses];
        
        [JSON[@"unspent_outputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *script = obj[@"script"];
            
            if (! [script hasSuffix:SCRIPT_SUFFIX] || script.length < SCRIPT_SUFFIX.length + 40) return;

            NSString *address = [[@"00" stringByAppendingString:[script
                                  substringWithRange:NSMakeRange(script.length - SCRIPT_SUFFIX.length - 40, 40)]]
                                 hexToBase58check];

            if (! addresses) return;
              
            if (! self.unspentOutputs[address]) self.unspentOutputs[address] = [NSMutableArray arrayWithObject:obj];
            else [self.unspentOutputs[address] addObject:obj];
        }];
        
        [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
          
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }] start];
}

- (id)init
{
    if (! (self = [super init])) return nil;
    
    self.defs = [NSUserDefaults standardUserDefaults];
    
    self.fundedAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:FUNDED_ADDRESSES_KEY]];
    self.spentAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:SPENT_ADDRESSES_KEY]];
    self.receiveAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:RECEIVE_ADDRESSES_KEY]];
    self.addressBalances = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_BALANCES_KEY]];
    self.unspentOutputs = [NSMutableDictionary dictionary];
    [[_defs dictionaryForKey:UNSPENT_OUTPUTS_KEY] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        self.unspentOutputs[key] = [NSMutableArray arrayWithArray:obj];
    }];
    
    [self queryAddresses:@[@"1T7cQHDFLuMVx77cDBn9jKkRQDuasXqt2", @"18WsLH7MjjrGE5LgyZHZVwwdRoSKLunYKk"]];
    
    return self;
}

- (id)initWithSeed:(NSString *)seed
{
    return [self init];
}
 
- (NSString *)transactionFor:(double)amount to:(NSString *)address
{
    long long amt = amount*SATOSHIS;
    long long balance = 0;

    NSArray *inputs =
    @[
        @{
            @"hash":@"4a89561dee3662fbb45a76626ac8e2fc9190d5716a082177231589edbf99a5a2",
            @"n":@0,
            //@"scriptSig":@"30440220134660b4124984f9a6de9b503252b32e3bb71edc3a00a86cec09ddef15b2d0bb0220478ca4e135692e8f9eaec908abece107ec2fa95a323e1dd2c910d4aef8d5648301 0462e841467e9a3cf122ef47846a5570ace550bcabe87ce28a0d8e546741c3df185bacecda840ba08e161d221833cdee49842ccc7ef2bb3f3d0796deaae662ef70",
            @"sequence_no":@(0xFFFFFFFF)
        },
    ];

    NSArray *outputs =
    @[
        @{
            @"value":@(amt),
            @"scriptPubKey":[NSString stringWithFormat:@"OP_DUP OP_HASH160 %@ OP_EQUALVERIFY OP_CHECKSIG",
                             [[address base58checkToHex] substringFromIndex:2]]
        },
        @{
            @"value":@(balance - amt),
            @"scriptPubKey":[NSString stringWithFormat:@"OP_DUP OP_HASH160 %@ OP_EQUALVERIFY OP_CHECKSIG",
                             [[self.receiveAddress base58checkToHex] substringFromIndex:2]]
        },
    ];

    NSDictionary *tx =
    @{
        @"ver":@1,
        @"vin_sz":@(inputs.count),
        @"in":inputs,
        @"vout_sz":@(outputs.count),
        @"out":outputs,
        @"lock_time":@0
    };

    NSLog(@"%@", tx);

    return [tx description];
}

@end
