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
              
            if (! [script hasPrefix:SCRIPT_PREFIX] || ! [script hasSuffix:SCRIPT_SUFFIX]) return;

            NSString *address = [[@"00" stringByAppendingString:[script
                                  substringWithRange:NSMakeRange(SCRIPT_PREFIX.length, 40)]] hexToBase58check];

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

/* sample tx:
{
    "hash":"31d6b7613dd3d024b4b0968dbdf66de9cfae6e2b55d67a1ab1d1eb6215197484",
    "ver":1,
    "vin_sz":2,
    "vout_sz":2,
    "lock_time":0,
    "size":979,
    "in":[
        {
            "prev_out":{
                "hash":"4a89561dee3662fbb45a76626ac8e2fc9190d5716a082177231589edbf99a5a2",
                "n":0
            },
            "scriptSig":"30440220134660b4124984f9a6de9b503252b32e3bb71edc3a00a86cec09ddef15b2d0bb0220478ca4e135692e8f9eaec908abece107ec2fa95a323e1dd2c910d4aef8d5648301 0462e841467e9a3cf122ef47846a5570ace550bcabe87ce28a0d8e546741c3df185bacecda840ba08e161d221833cdee49842ccc7ef2bb3f3d0796deaae662ef70"
        },
        {
            "prev_out":{
                "hash":"86b8d94a542df7f9660f855c5152a62639bdd3e75216217a91658925069334cf",
                "n":0
            },
            "scriptSig":"3046022100fd63b1d55982df669f67d255c90e111d21b1212eec6f6935020c787002687f04022100cc0b3bf3ca18371661e13fd1b69287854ff95cf945bcdb2d97233dc2345aff7a01 046b747ab57d936b9fdcaf52ee2d3fa7fcb0e3f04dc7c0e61d0e1f42f70213a3d991eef23320410cc85060d885278aabb0f80fe9ad3f81e116a60ba397f3c7faf9"
        }
    ],
    "out":[
        {
            "value":"0.04888263",
            "scriptPubKey":"OP_DUP OP_HASH160 e4ae3e8a99f8b44a5032f92a42e80458376033d4 OP_EQUALVERIFY OP_CHECKSIG"
        },
        {
            "value":"52.16780000",
            "scriptPubKey":"OP_DUP OP_HASH160 4c493309671c0d7faf273e2ecf50606327e3fc7f OP_EQUALVERIFY OP_CHECKSIG"
        }
    ]
}
*/
 
- (NSString *)transactionFor:(double)amount to:(NSString *)address
{
    NSArray *inputs =
    @[
        @{
            @"prev_out":@{
                @"hash":@"4a89561dee3662fbb45a76626ac8e2fc9190d5716a082177231589edbf99a5a2",
                @"n":@0
            },
            //@"scriptSig":@"30440220134660b4124984f9a6de9b503252b32e3bb71edc3a00a86cec09ddef15b2d0bb0220478ca4e135692e8f9eaec908abece107ec2fa95a323e1dd2c910d4aef8d5648301 0462e841467e9a3cf122ef47846a5570ace550bcabe87ce28a0d8e546741c3df185bacecda840ba08e161d221833cdee49842ccc7ef2bb3f3d0796deaae662ef70"
        },
    ];

    NSArray *outputs =
    @[
        @{
            @"value":@(amount),
            @"scriptPubKey":[NSString stringWithFormat:@"OP_DUP OP_HASH160 %@ OP_EQUALVERIFY OP_CHECKSIG",
                             [[address base58checkToHex] substringFromIndex:2]]
        },
    ];

    NSDictionary *tx =
    @{
        @"hash":@"31d6b7613dd3d024b4b0968dbdf66de9cfae6e2b55d67a1ab1d1eb6215197484",
        @"ver":@1,
        @"vin_sz":@(inputs.count),
        @"vout_sz":@(outputs.count),
        @"lock_time":@0,
        @"size":@979,
        @"in":inputs,
        @"out":outputs
    };

    NSLog(@"%@", tx);

    return [tx description];
}

@end
