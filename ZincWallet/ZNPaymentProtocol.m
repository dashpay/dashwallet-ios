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

#define pbString(d) [[NSString alloc] initWithData:(d) encoding:NSUTF8StringEncoding]
#define pbSInt(i)   (((i) >> 1) ^ -((i) & 1))

@interface NSData (ProtoBuf)

- (uint64_t)pbVarIntAtOffeset:(NSUInteger *)off;
- (uint64_t)pb64BitAtOffeset:(NSUInteger *)off;
- (NSData *)pbLenDelimAtOffeset:(NSUInteger *)off;
- (uint32_t)pb32BitAtOffeset:(NSUInteger *)off;
- (NSUInteger)pbFieldAtOffset:(NSUInteger *)off int:(uint64_t *)i data:(NSData **)d;

@end

@implementation NSData (ProtoBuf)

- (uint64_t)pbVarIntAtOffeset:(NSUInteger *)off
{
    uint64_t r = 0;
    uint8_t b = 0x80, i = 0;

    while ((b & 0x80) && *off < self.length) {
        b = ((const uint8_t *)self.bytes)[(*off)++];
        r += (uint64_t)(b & 0x7f) << 7*i++;
    }

    return r;
}

- (uint64_t)pb64BitAtOffeset:(NSUInteger *)off
{
    uint64_t r = 0;

    if (*off + sizeof(uint64_t) <= self.length) r = *(const uint64_t *)((const uint8_t *)self.bytes + *off);
    *off += sizeof(uint64_t);

    return CFSwapInt64LittleToHost(r);
}

- (NSData *)pbLenDelimAtOffeset:(NSUInteger *)off
{
    NSData *r = nil;
    NSUInteger l = [self pbVarIntAtOffeset:off];

    if (*off + l <= self.length) r = [self subdataWithRange:NSMakeRange(*off, l)];
    *off += l;

    return r;
}

- (uint32_t)pb32BitAtOffeset:(NSUInteger *)off
{
    uint32_t r = 0;

    if (*off + sizeof(uint32_t) <= self.length) r = *(const uint64_t *)((const uint8_t *)self.bytes + *off);
    *off += sizeof(uint32_t);

    return CFSwapInt32LittleToHost(r);
}

- (NSUInteger)pbFieldAtOffset:(NSUInteger *)off int:(uint64_t *)i data:(NSData **)d
{
    NSUInteger key = [self pbVarIntAtOffeset:off];

    switch (key & 0x7) {
        case PROTOBUF_VARINT: if (i) *i = [self pbVarIntAtOffeset:off]; break;
        case PROTOBUF_64BIT: if (i) *i = [self pb64BitAtOffeset:off]; break;
        case PROTOBUF_LENDELIM: if (d) *d = [self pbLenDelimAtOffeset:off]; break;
        case PROTOBUF_32BIT: if (i) *i = [self pb32BitAtOffeset:off]; break;
        default: break;
    }

    return key >> 3;
}

@end

@interface NSMutableData (ProtoBuf)

- (void)pbAppendVarInt:(uint64_t)i;
- (void)pbAppend64Bit:(uint64_t)i;
- (void)pbAppendLenDelim:(NSData *)d;
- (void)pbAppend32Bit:(uint32_t)i;
- (void)pbAppendString:(NSString *)s withKey:(NSUInteger)key;
- (void)pbAppendData:(NSData *)d withKey:(NSUInteger)key;
- (void)pbAppendInt:(uint64_t)i withKey:(NSUInteger)key;
- (void)pbAppendSInt:(int64_t)i withKey:(NSUInteger)key;

@end

@implementation NSMutableData (ProtoBuf)

- (void)pbAppendVarInt:(uint64_t)i
{
    do {
        uint8_t b = i & 0x7f;

        i >>= 7;
        if (i > 0) b &= 0x80;
        [self appendBytes:&b length:1];
    } while (i > 0);
}

- (void)pbAppend64Bit:(uint64_t)i
{
    i = CFSwapInt64HostToLittle(i);
    [self appendBytes:&i length:sizeof(i)];
}

- (void)pbAppendLenDelim:(NSData *)d
{
    [self pbAppendVarInt:d.length];
    [self appendData:d];
}

- (void)pbAppend32Bit:(uint32_t)i
{
    i = CFSwapInt32HostToLittle(i);
    [self appendBytes:&i length:sizeof(i)];
}

- (void)pbAppendString:(NSString *)s withKey:(NSUInteger)key
{
    [self pbAppendVarInt:(key << 3) + PROTOBUF_LENDELIM];
    [self pbAppendLenDelim:[s dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)pbAppendData:(NSData *)d withKey:(NSUInteger)key
{
    [self pbAppendVarInt:(key << 3) + PROTOBUF_LENDELIM];
    [self pbAppendLenDelim:d];
}

- (void)pbAppendInt:(uint64_t)i withKey:(NSUInteger)key
{
    [self pbAppendVarInt:(key << 3) + PROTOBUF_VARINT];
    [self pbAppendVarInt:i];
}

- (void)pbAppendSInt:(int64_t)i withKey:(NSUInteger)key
{
    [self pbAppendVarInt:(key << 3) + PROTOBUF_VARINT];
    [self pbAppendVarInt:(*(uint64_t *)&i >> 1) ^ -(i & 1)];
}

@end

typedef enum {
    output_amount = 1,
    output_script = 2
} output_t;

static void parseOutput(NSData *data, uint64_t *amount, NSData **script)
{
    NSUInteger off = 0;

    *amount = 0; // default
    *script = [NSData data];

    while (off < data.length) {
        uint64_t i = 0;
        NSData *d = nil;
        output_t key = [data pbFieldAtOffset:&off int:&i data:&d];

        switch (key) {
            case output_amount: *amount = i; break;
            case output_script: if (d) *script = d; break;
            default: break;
        }
    }
}

static NSData *serializeOutput(uint64_t amount, NSData *script)
{
    NSMutableData *d = [NSMutableData data];

    [d pbAppendInt:amount withKey:output_amount];
    [d pbAppendData:script withKey:output_script];

    return d;
}

typedef enum {
    details_network = 1,
    details_outputs = 2,
    details_time = 3,
    details_expires = 4,
    details_memo = 5,
    details_payment_url = 6,
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
    NSMutableArray *amounts = [NSMutableArray array], *scripts = [NSMutableArray array];

    while (off < data.length) {
        uint64_t i = 0;
        NSData *d = nil;
        details_t key = [data pbFieldAtOffset:&off int:&i data:&d];
        uint64_t amount = 0;
        NSData *script = nil;

        switch (key) {
            case details_network: if (d) _network = pbString(d); break;
            case details_outputs: if (d) parseOutput(d, &amount, &script); break;
            case details_time: if (i) _time = i - NSTimeIntervalSince1970; break;
            case details_expires: if (i) _expires = i - NSTimeIntervalSince1970; break;
            case details_memo: if (d) _memo = pbString(d); break;
            case details_payment_url: if (d) _paymentURL = pbString(d); break;
            case details_merchant_data: if (d) _merchantData = d; break;
            default: break;
        }

        if (script) [amounts addObject:@(amount)], [scripts addObject:script];
    }

    _outputAmounts = amounts;
    _outputScripts = scripts;

    return self;
}

- (NSData *)toData
{
    NSMutableData *d = [NSMutableData data];
    NSUInteger i = 0;

    [d pbAppendString:_network withKey:details_network];

    for (NSData *s in _outputScripts) {
        [d pbAppendData:serializeOutput([_outputAmounts[i++] unsignedLongLongValue], s) withKey:details_outputs];
    }

    [d pbAppendInt:_time + NSTimeIntervalSince1970 withKey:details_time];
    [d pbAppendInt:_expires + NSTimeIntervalSince1970 withKey:details_expires];
    if (_memo) [d pbAppendString:_memo withKey:details_memo];
    if (_paymentURL) [d pbAppendString:_paymentURL withKey:details_payment_url];
    if (_merchantData) [d pbAppendData:_merchantData withKey:details_merchant_data];

    return d;
}

@end

typedef enum {
    request_version = 1,
    request_pki_type = 2,
    request_pki_data = 3,
    request_details = 4,
    request_signature = 5
} request_t;

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

    while (off < data.length) {
        uint64_t i = 0;
        NSData *d = nil;
        request_t key = [data pbFieldAtOffset:&off int:&i data:&d];

        switch (key) {
            case request_version: if (i) _version = i; break;
            case request_pki_type: if (d) _pkiType = pbString(d); break;
            case request_pki_data: if (d) _pkiData = d; break;
            case request_details: if (d) _details = [ZNPaymentProtocolDetails detailsWithData:d]; break;
            case request_signature: if (d) _signature = d; break;
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

    if (version) _version = version;
    if (type) _pkiType = type;
    _pkiData = data;
    _details = details;
    _signature = sig;

    return self;
}

- (NSData *)toData
{
    NSMutableData *d = [NSMutableData data];

    [d pbAppendInt:_version withKey:request_version];
    [d pbAppendString:_pkiType withKey:request_pki_type];
    if (_pkiData) [d pbAppendData:_pkiData withKey:request_pki_data];
    [d pbAppendData:_details.data withKey:request_details];
    if (_signature) [d pbAppendData:_signature withKey:request_signature];

    return d;
}

@end

typedef enum {
    payment_merchant_data = 1,
    payment_transactions = 2,
    payment_refund_to = 3,
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
    NSMutableArray *txs = [NSMutableArray array], *amounts = [NSMutableArray array], *scripts = [NSMutableArray array];

    while (off < data.length) {
        uint64_t i = 0;
        NSData *d = nil;
        payment_t key = [data pbFieldAtOffset:&off int:&i data:&d];
        ZNTransaction *tx = nil;
        uint64_t amount = 0;
        NSData *script = nil;

        switch (key) {
            case payment_merchant_data: if (d) _merchantData = d; break;
            case payment_transactions: if (d) tx = [ZNTransaction transactionWithMessage:d]; break;
            case payment_refund_to: if (d) parseOutput(d, &amount, &script); break;
            case payment_memo: if (d) _memo = pbString(d); break;
            default: break;
        }

        if (tx) [txs addObject:tx];
        if (script) [amounts addObject:@(amount)], [scripts addObject:script];
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
    NSMutableData *d = [NSMutableData data];
    NSUInteger i = 0;

    if (_merchantData) [d pbAppendData:_merchantData withKey:payment_merchant_data];

    for (ZNTransaction *tx in _transactions) {
        [d pbAppendData:tx.data withKey:payment_transactions];
    }

    for (NSData *s in _refundToScripts) {
        [d pbAppendData:serializeOutput([_refundToAmounts[i++] unsignedLongLongValue], s) withKey:payment_refund_to];
    }

    if (_memo) [d pbAppendString:_memo withKey:payment_memo];

    return d;
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

    while (off < data.length) {
        uint64_t i = 0;
        NSData *d = nil;
        ack_t key = [data pbFieldAtOffset:&off int:&i data:&d];

        switch (key) {
            case ack_payment: if (d) _payment = [ZNPaymentProtocolPayment paymentWithData:d]; break;
            case ack_memo: if (d) _memo = pbString(d); break;
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
    NSMutableData *d = [NSMutableData data];

    [d pbAppendData:_payment.data withKey:ack_payment];
    if (_memo) [d pbAppendString:_memo withKey:ack_memo];

    return d;
}

@end
