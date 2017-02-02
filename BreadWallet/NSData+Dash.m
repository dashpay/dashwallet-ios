//
//  NSData+Dash.m
//  BreadWallet
//
//  Created by Sam Westrich on 1/31/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
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

#import "NSData+Dash.h"
#import "Blake.c"
#import "Bmw.c"
#import "CubeHash.c"
#import "Groestl.c"
#import "Echo.c"
#import "Jh.c"
#import "Keccak.c"
#import "Luffa.c"
#import "Shavite.c"
#import "Simd.c"
#import "Skein.c"

@implementation NSData (Dash)

- (UInt256)x11
{

    UInt512 x11Data;
    
    sph_blake_big_context ctx_blake;
    sph_blake512_init(&ctx_blake);
    sph_blake512(&ctx_blake, self.bytes, 64);
    sph_blake512_close(&ctx_blake, &x11Data);
    
    sph_bmw_big_context ctx_bmw;
    sph_bmw512_init(&ctx_bmw);
    sph_bmw512(&ctx_bmw, &x11Data, 64);
    sph_bmw512_close(&ctx_bmw, &x11Data);
    
    sph_groestl_big_context ctx_groestl;
    sph_groestl512_init(&ctx_groestl);
    sph_groestl512(&ctx_groestl, &x11Data, 64);
    sph_groestl512_close(&ctx_groestl, &x11Data);
    
    sph_skein_big_context ctx_skein;
    sph_skein512_init(&ctx_skein);
    sph_skein512(&ctx_skein, &x11Data, 64);
    sph_skein512_close(&ctx_skein, &x11Data);
    
    sph_jh_context ctx_jh;
    sph_jh512_init(&ctx_jh);
    sph_jh512(&ctx_jh, &x11Data, 64);
    sph_jh512_close(&ctx_jh, &x11Data);
    
    sph_keccak_context ctx_keccak;
    sph_keccak512_init(&ctx_keccak);
    sph_keccak512(&ctx_keccak, &x11Data, 64);
    sph_keccak512_close(&ctx_keccak, &x11Data);
    
    sph_luffa512_context ctx_luffa;
    sph_luffa512_init(&ctx_luffa);
    sph_luffa512(&ctx_luffa, &x11Data, 64);
    sph_luffa512_close(&ctx_luffa, &x11Data);
    
    sph_cubehash_context ctx_cubehash;
    sph_cubehash512_init(&ctx_cubehash);
    sph_cubehash512(&ctx_cubehash, &x11Data, 64);
    sph_cubehash512_close(&ctx_cubehash, &x11Data);
    
    sph_shavite_big_context ctx_shavite;
    sph_shavite512_init(&ctx_shavite);
    sph_shavite512(&ctx_shavite, &x11Data, 64);
    sph_shavite512_close(&ctx_shavite, &x11Data);
    
    sph_simd_big_context ctx_simd;
    sph_simd512_init(&ctx_simd);
    sph_simd512(&ctx_simd, &x11Data, 64);
    sph_simd512_close(&ctx_simd, &x11Data);
    
    UInt256 rData;
    
    sph_echo_big_context ctx_echo;
    sph_echo512_init(&ctx_echo);
    sph_echo512(&ctx_echo, &x11Data, 32);
    sph_echo512_close(&ctx_echo, &rData);
    

    return rData;
    
}

@end
