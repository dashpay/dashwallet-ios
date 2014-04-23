//
//  ZNPaymentProtocol.m
//  ZincWallet
//
//  Created by Aaron Voisine on 4/21/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import "ZNPaymentProtocol.h"
#import "ZNTransaction.h"

// BIP70 payment protocol: https://github.com/bitcoin/bips/blob/master/bip-0070.mediawiki

#define PROTOBUF_VARINT   0 // int32, int64, uint32, uint64, sint32, sint64, bool, enum
#define PROTOBUF_64BIT    1 // fixed64, sfixed64, double
#define PROTOBUF_LENDELIM 2 // string, bytes, embedded messages, packed repeated fields
#define PROTOBUF_32BIT    5 // fixed32, sfixed32, float

static uint64_t protoBufVarInt(NSData *d, NSUInteger *off)
{
    uint64_t r = 0;
    uint8_t b = 0x80, i = 0;

    while ((b & 0x80) && *off < d.length) {
        b = ((const uint8_t *)d.bytes)[(*off)++];
        r += (uint64_t)(b & 0x7f) << 7*i++;
    }

    return r;
}

static NSData *protoBufLenDelim(NSData *d, NSUInteger *off)
{
    NSData *r = nil;
    NSUInteger l = protoBufVarInt(d, off);

    if (*off + l <= d.length) r = [d subdataWithRange:NSMakeRange(*off, l)];
    *off += l;

    return r;
}

static id protoBufField(NSData *d, NSUInteger *off, NSUInteger *key)
{
    id r = nil;

    *key = protoBufVarInt(d, off);

    switch (*key & 0x7) {
        case PROTOBUF_VARINT: r = @(protoBufVarInt(d, off)); break;
        case PROTOBUF_64BIT: *off += sizeof(uint64_t); break; // not used by BIP70
        case PROTOBUF_LENDELIM: r = protoBufLenDelim(d, off); break;
        case PROTOBUF_32BIT: *off += sizeof(uint32_t); break; // not used by BIP70
        default: break;
    }
    
    *key >>= 3;

    return r;
}

typedef enum {
    output_amount = 1,
    output_script = 2
} output_t;

static void addOutput(NSData *d, NSMutableArray *amounts, NSMutableArray *scripts)
{
    NSUInteger off = 0;
    output_t key;
    NSNumber *amount = @(0); // default
    NSData *script = [NSData data];

    while (off < d.length) {
        id field = protoBufField(d, &off, &key);

        switch (key) {
            case output_amount: amount = field; break;
            case output_script: script = field; break;
            default: break;
        }
    }

    [amounts addObject:amount];
    [scripts addObject:script];
}

typedef enum {
    details_network = 1,
    details_outputs = 2,
    details_time = 3,
    details_expires = 4,
    details_memo = 5,
    details_url = 6,
    details_merchant_data = 7
} details_t;

@implementation ZNPaymentProtocolDetails

+ (instancetype)detailsWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    _network = @"main"; // default

    return self;
}

- (instancetype)initWithNetwork:(NSString *)network outputAmounts:(NSArray *)amounts outputScripts:(NSArray *)scripts
time:(NSTimeInterval)time expires:(NSTimeInterval)expires memo:(NSString *)memo paymentURL:(NSString *)url
merchantData:(NSData *)data
{
    if (amounts.count != scripts.count) return nil;
    if (! (self = [self init])) return nil;

    if (network) _network = network;
    _outputAmounts = amounts;
    _outputScripts = scripts;
    _time = time;
    _expires = expires;
    _memo = memo;
    _paymentURL = url;

    return self;
}

- (instancetype)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    NSUInteger off = 0;
    details_t key;
    NSMutableArray *amounts = [NSMutableArray array], *scripts = [NSMutableArray array];

    while (off < data.length) {
        id field = protoBufField(data, &off, &key);

        switch (key) {
            case details_network: _network = [[NSString alloc] initWithData:field encoding:NSUTF8StringEncoding]; break;
            case details_outputs: addOutput(field, amounts, scripts); break;
            case details_time: _time = [field doubleValue] - NSTimeIntervalSince1970; break;
            case details_expires: _expires = [field doubleValue] - NSTimeIntervalSince1970; break;
            case details_memo: _memo = [[NSString alloc] initWithData:field encoding:NSUTF8StringEncoding]; break;
            case details_url: _paymentURL = [[NSString alloc] initWithData:field encoding:NSUTF8StringEncoding]; break;
            case details_merchant_data: _merchantData = field; break;
            default: break;
        }
    }

    _outputAmounts = amounts;
    _outputScripts = scripts;

    return self;
}

- (NSData *)toData
{
    return nil;
}

@end

typedef enum {
    request_version = 1,
    request_pki_type = 2,
    request_pki_data = 3,
    request_details = 4,
    request_signature = 5
} request_t;

typedef enum {
    certificate_cert = 1
} certificate_t;

@implementation ZNPaymentProtocolRequest

+ (instancetype)requestWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    _version = 1; // default
    _pkiType = @"none"; // default

    return self;
}

- (instancetype)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    NSUInteger off = 0;
    request_t key;

    while (off < data.length) {
        id field = protoBufField(data, &off, &key);

        switch (key) {
            case request_version: _version = [field unsignedIntValue]; break;
            case request_pki_type: _pkiType = [[NSString alloc] initWithData:field encoding:NSUTF8StringEncoding];break;
            case request_pki_data: _pkiData = field; break;
            case request_details: _details = [ZNPaymentProtocolDetails detailsWithData:field]; break;
            case request_signature: _signature = field; break;
            default: break;
        }
    }

    if (! _details) return nil; // required

    return self;
}

- (instancetype)initWithVersion:(uint32_t)version pkiType:(NSString *)type pkiData:(NSData *)data
details:(ZNPaymentProtocolDetails *)details signature:(NSData *)sig
{
    if (! details) return nil; // required
    if (! (self = [self init])) return nil;

    _version = version;
    if (type) _pkiType = type;
    _pkiData = data;
    _details = details;
    _signature = sig;

    return self;
}

- (NSData *)toData
{
    return nil;
}

@end

typedef enum {
    payment_merchant_data = 1,
    payment_transactions = 2,
    payment_refund = 3,
    payment_memo = 4
} payment_t;

@implementation ZNPaymentProtocolPayment

+ (instancetype)paymentWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (instancetype)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    NSUInteger off = 0;
    payment_t key;
    NSMutableArray *txs = [NSMutableArray array], *amounts = [NSMutableArray array], *scripts = [NSMutableArray array];

    while (off < data.length) {
        id field = protoBufField(data, &off, &key);
        ZNTransaction *tx = nil;

        switch (key) {
            case payment_merchant_data: _merchantData = field; break;
            case payment_transactions: tx = [ZNTransaction transactionWithMessage:field]; break;
            case payment_refund: addOutput(field, amounts, scripts); break;
            case payment_memo: _memo = [[NSString alloc] initWithData:field encoding:NSUTF8StringEncoding]; break;
            default: break;
        }

        if (tx) [txs addObject:tx];
    }

    _transactions = txs;
    _refundToAmounts = amounts;
    _refundToScripts = scripts;

    return self;
}

- (instancetype)initWithMerchantData:(NSData *)data transactions:(NSArray *)transactions
refundToAmounts:(NSArray *)amounts refundToScripts:(NSArray *)scripts memo:(NSString *)memo
{
    if (amounts.count != scripts.count) return nil;
    if (! (self = [self init])) return nil;

    _merchantData = data;
    _transactions = transactions;
    _refundToAmounts = amounts;
    _refundToScripts = scripts;
    _memo = memo;

    return self;
}

- (NSData *)toData
{
    return nil;
}

@end

typedef enum {
    ack_payment = 1,
    ack_memo = 2
} ack_t;

@implementation ZNPaymentProtocolACK

+ (instancetype)ackWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (instancetype)initWithData:(NSData *)data
{
    if (! (self = [self init])) return nil;

    NSUInteger off = 0;
    ack_t key;

    while (off < data.length) {
        id field = protoBufField(data, &off, &key);

        switch (key) {
            case ack_payment: _payment = [ZNPaymentProtocolPayment paymentWithData:field]; break;
            case ack_memo: _memo = [[NSString alloc] initWithData:field encoding:NSUTF8StringEncoding];break;
            default: break;
        }
    }

    if (! _payment) return nil; // required

    return self;
}

- (instancetype)initWithPayment:(ZNPaymentProtocolPayment *)payment andMemo:(NSString *)memo
{
    if (! payment) return nil; // required
    if (! (self = [self init])) return nil;

    _payment = payment;
    _memo = memo;

    return self;
}

- (NSData *)toData
{
    return nil;
}

@end
