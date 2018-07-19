//
//  Blake.h
//  DashWallet
//
/* $Id: blake.c 252 2011-06-07 17:55:14Z tp $ */
/*
 * BLAKE implementation.
 *
 * ==========================(LICENSE BEGIN)============================
 *
 * Copyright (c) 2007-2010  Projet RNRT SAPHIR
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * ===========================(LICENSE END)=============================
 *
 * @author   Thomas Pornin <thomas.pornin@cryptolog.com>
 */


#include "sph_types.h"

#ifndef X11_BLAKE
#define X11_BLAKE 1

typedef struct {
#ifndef DOXYGEN_IGNORE
    unsigned char buf[128];    /* first field, for alignment */
    size_t ptr;
    sph_u64 H[8];
    sph_u64 S[4];
    sph_u64 T0, T1;
#endif
} sph_blake_big_context;

static const sph_u64 blakeIV512[8] = {
    SPH_C64(0x6A09E667F3BCC908), SPH_C64(0xBB67AE8584CAA73B),
    SPH_C64(0x3C6EF372FE94F82B), SPH_C64(0xA54FF53A5F1D36F1),
    SPH_C64(0x510E527FADE682D1), SPH_C64(0x9B05688C2B3E6C1F),
    SPH_C64(0x1F83D9ABFB41BD6B), SPH_C64(0x5BE0CD19137E2179)
};

#define Z00   0
#define Z01   1
#define Z02   2
#define Z03   3
#define Z04   4
#define Z05   5
#define Z06   6
#define Z07   7
#define Z08   8
#define Z09   9
#define Z0A   A
#define Z0B   B
#define Z0C   C
#define Z0D   D
#define Z0E   E
#define Z0F   F

#define Z10   E
#define Z11   A
#define Z12   4
#define Z13   8
#define Z14   9
#define Z15   F
#define Z16   D
#define Z17   6
#define Z18   1
#define Z19   C
#define Z1A   0
#define Z1B   2
#define Z1C   B
#define Z1D   7
#define Z1E   5
#define Z1F   3

#define Z20   B
#define Z21   8
#define Z22   C
#define Z23   0
#define Z24   5
#define Z25   2
#define Z26   F
#define Z27   D
#define Z28   A
#define Z29   E
#define Z2A   3
#define Z2B   6
#define Z2C   7
#define Z2D   1
#define Z2E   9
#define Z2F   4

#define Z30   7
#define Z31   9
#define Z32   3
#define Z33   1
#define Z34   D
#define Z35   C
#define Z36   B
#define Z37   E
#define Z38   2
#define Z39   6
#define Z3A   5
#define Z3B   A
#define Z3C   4
#define Z3D   0
#define Z3E   F
#define Z3F   8

#define Z40   9
#define Z41   0
#define Z42   5
#define Z43   7
#define Z44   2
#define Z45   4
#define Z46   A
#define Z47   F
#define Z48   E
#define Z49   1
#define Z4A   B
#define Z4B   C
#define Z4C   6
#define Z4D   8
#define Z4E   3
#define Z4F   D

#define Z50   2
#define Z51   C
#define Z52   6
#define Z53   A
#define Z54   0
#define Z55   B
#define Z56   8
#define Z57   3
#define Z58   4
#define Z59   D
#define Z5A   7
#define Z5B   5
#define Z5C   F
#define Z5D   E
#define Z5E   1
#define Z5F   9

#define Z60   C
#define Z61   5
#define Z62   1
#define Z63   F
#define Z64   E
#define Z65   D
#define Z66   4
#define Z67   A
#define Z68   0
#define Z69   7
#define Z6A   6
#define Z6B   3
#define Z6C   9
#define Z6D   2
#define Z6E   8
#define Z6F   B

#define Z70   D
#define Z71   B
#define Z72   7
#define Z73   E
#define Z74   C
#define Z75   1
#define Z76   3
#define Z77   9
#define Z78   5
#define Z79   0
#define Z7A   F
#define Z7B   4
#define Z7C   8
#define Z7D   6
#define Z7E   2
#define Z7F   A

#define Z80   6
#define Z81   F
#define Z82   E
#define Z83   9
#define Z84   B
#define Z85   3
#define Z86   0
#define Z87   8
#define Z88   C
#define Z89   2
#define Z8A   D
#define Z8B   7
#define Z8C   1
#define Z8D   4
#define Z8E   A
#define Z8F   5

#define Z90   A
#define Z91   2
#define Z92   8
#define Z93   4
#define Z94   7
#define Z95   6
#define Z96   1
#define Z97   5
#define Z98   F
#define Z99   B
#define Z9A   9
#define Z9B   E
#define Z9C   3
#define Z9D   C
#define Z9E   D
#define Z9F   0

#define Mx(r, i)    Mx_(Z ## r ## i)
#define Mx_(n)      Mx__(n)
#define Mx__(n)     M ## n

#define CBx(r, i)   CBx_(Z ## r ## i)
#define CBx_(n)     CBx__(n)
#define CBx__(n)    CB ## n

#define CB0   SPH_C64(0x243F6A8885A308D3)
#define CB1   SPH_C64(0x13198A2E03707344)
#define CB2   SPH_C64(0xA4093822299F31D0)
#define CB3   SPH_C64(0x082EFA98EC4E6C89)
#define CB4   SPH_C64(0x452821E638D01377)
#define CB5   SPH_C64(0xBE5466CF34E90C6C)
#define CB6   SPH_C64(0xC0AC29B7C97C50DD)
#define CB7   SPH_C64(0x3F84D5B5B5470917)
#define CB8   SPH_C64(0x9216D5D98979FB1B)
#define CB9   SPH_C64(0xD1310BA698DFB5AC)
#define CBA   SPH_C64(0x2FFD72DBD01ADFB7)
#define CBB   SPH_C64(0xB8E1AFED6A267E96)
#define CBC   SPH_C64(0xBA7C9045F12C7F99)
#define CBD   SPH_C64(0x24A19947B3916CF7)
#define CBE   SPH_C64(0x0801F2E2858EFC16)
#define CBF   SPH_C64(0x636920D871574E69)

#define GB(m0, m1, c0, c1, a, b, c, d)   do { \
a = SPH_T64(a + b + (m0 ^ c1)); \
d = SPH_ROTR64(d ^ a, 32); \
c = SPH_T64(c + d); \
b = SPH_ROTR64(b ^ c, 25); \
a = SPH_T64(a + b + (m1 ^ c0)); \
d = SPH_ROTR64(d ^ a, 16); \
c = SPH_T64(c + d); \
b = SPH_ROTR64(b ^ c, 11); \
} while (0)

#define ROUND_B(r)   do { \
GB(Mx(r, 0), Mx(r, 1), CBx(r, 0), CBx(r, 1), V0, V4, V8, VC); \
GB(Mx(r, 2), Mx(r, 3), CBx(r, 2), CBx(r, 3), V1, V5, V9, VD); \
GB(Mx(r, 4), Mx(r, 5), CBx(r, 4), CBx(r, 5), V2, V6, VA, VE); \
GB(Mx(r, 6), Mx(r, 7), CBx(r, 6), CBx(r, 7), V3, V7, VB, VF); \
GB(Mx(r, 8), Mx(r, 9), CBx(r, 8), CBx(r, 9), V0, V5, VA, VF); \
GB(Mx(r, A), Mx(r, B), CBx(r, A), CBx(r, B), V1, V6, VB, VC); \
GB(Mx(r, C), Mx(r, D), CBx(r, C), CBx(r, D), V2, V7, V8, VD); \
GB(Mx(r, E), Mx(r, F), CBx(r, E), CBx(r, F), V3, V4, V9, VE); \
} while (0)

#define BLAKE_DECL_STATE64 \
sph_u64 H0, H1, H2, H3, H4, H5, H6, H7; \
sph_u64 S0, S1, S2, S3, T0, T1;

#define BLAKE_READ_STATE64(state)   do { \
H0 = (state)->H[0]; \
H1 = (state)->H[1]; \
H2 = (state)->H[2]; \
H3 = (state)->H[3]; \
H4 = (state)->H[4]; \
H5 = (state)->H[5]; \
H6 = (state)->H[6]; \
H7 = (state)->H[7]; \
S0 = (state)->S[0]; \
S1 = (state)->S[1]; \
S2 = (state)->S[2]; \
S3 = (state)->S[3]; \
T0 = (state)->T0; \
T1 = (state)->T1; \
} while (0)

#define BLAKE_WRITE_STATE64(state)   do { \
(state)->H[0] = H0; \
(state)->H[1] = H1; \
(state)->H[2] = H2; \
(state)->H[3] = H3; \
(state)->H[4] = H4; \
(state)->H[5] = H5; \
(state)->H[6] = H6; \
(state)->H[7] = H7; \
(state)->S[0] = S0; \
(state)->S[1] = S1; \
(state)->S[2] = S2; \
(state)->S[3] = S3; \
(state)->T0 = T0; \
(state)->T1 = T1; \
} while (0)

#define COMPRESS64   do { \
sph_u64 M0, M1, M2, M3, M4, M5, M6, M7; \
sph_u64 M8, M9, MA, MB, MC, MD, ME, MF; \
sph_u64 V0, V1, V2, V3, V4, V5, V6, V7; \
sph_u64 V8, V9, VA, VB, VC, VD, VE, VF; \
V0 = H0; \
V1 = H1; \
V2 = H2; \
V3 = H3; \
V4 = H4; \
V5 = H5; \
V6 = H6; \
V7 = H7; \
V8 = S0 ^ CB0; \
V9 = S1 ^ CB1; \
VA = S2 ^ CB2; \
VB = S3 ^ CB3; \
VC = T0 ^ CB4; \
VD = T0 ^ CB5; \
VE = T1 ^ CB6; \
VF = T1 ^ CB7; \
M0 = sph_dec64be_aligned(buf +   0); \
M1 = sph_dec64be_aligned(buf +   8); \
M2 = sph_dec64be_aligned(buf +  16); \
M3 = sph_dec64be_aligned(buf +  24); \
M4 = sph_dec64be_aligned(buf +  32); \
M5 = sph_dec64be_aligned(buf +  40); \
M6 = sph_dec64be_aligned(buf +  48); \
M7 = sph_dec64be_aligned(buf +  56); \
M8 = sph_dec64be_aligned(buf +  64); \
M9 = sph_dec64be_aligned(buf +  72); \
MA = sph_dec64be_aligned(buf +  80); \
MB = sph_dec64be_aligned(buf +  88); \
MC = sph_dec64be_aligned(buf +  96); \
MD = sph_dec64be_aligned(buf + 104); \
ME = sph_dec64be_aligned(buf + 112); \
MF = sph_dec64be_aligned(buf + 120); \
ROUND_B(0); \
ROUND_B(1); \
ROUND_B(2); \
ROUND_B(3); \
ROUND_B(4); \
ROUND_B(5); \
ROUND_B(6); \
ROUND_B(7); \
ROUND_B(8); \
ROUND_B(9); \
ROUND_B(0); \
ROUND_B(1); \
ROUND_B(2); \
ROUND_B(3); \
ROUND_B(4); \
ROUND_B(5); \
H0 ^= S0 ^ V0 ^ V8; \
H1 ^= S1 ^ V1 ^ V9; \
H2 ^= S2 ^ V2 ^ VA; \
H3 ^= S3 ^ V3 ^ VB; \
H4 ^= S0 ^ V4 ^ VC; \
H5 ^= S1 ^ V5 ^ VD; \
H6 ^= S2 ^ V6 ^ VE; \
H7 ^= S3 ^ V7 ^ VF; \
} while (0)


static const sph_u64 salt_zero_big[4] = { 0, 0, 0, 0 };

static void
blake64_init(sph_blake_big_context *sc,
             const sph_u64 *iv, const sph_u64 *salt)
{
    memcpy(sc->H, iv, 8 * sizeof(sph_u64));
    memcpy(sc->S, salt, 4 * sizeof(sph_u64));
    sc->T0 = sc->T1 = 0;
    sc->ptr = 0;
}

static void
blake64(sph_blake_big_context *sc, const void *data, size_t len)
{
    unsigned char *buf;
    size_t ptr;
    BLAKE_DECL_STATE64
    
    buf = sc->buf;
    ptr = sc->ptr;
    if (len < (sizeof sc->buf) - ptr) {
        memcpy(buf + ptr, data, len);
        ptr += len;
        sc->ptr = ptr;
        return;
    }
    
    BLAKE_READ_STATE64(sc);
    while (len > 0) {
        size_t clen;
        
        clen = (sizeof sc->buf) - ptr;
        if (clen > len)
            clen = len;
        memcpy(buf + ptr, data, clen);
        ptr += clen;
        data = (const unsigned char *)data + clen;
        len -= clen;
        if (ptr == sizeof sc->buf) {
            if ((T0 = SPH_T64(T0 + 1024)) < 1024)
                T1 = SPH_T64(T1 + 1);
            COMPRESS64;
            ptr = 0;
        }
    }
    BLAKE_WRITE_STATE64(sc);
    sc->ptr = ptr;
}

static void
blake64_close(sph_blake_big_context *sc,
              unsigned ub, unsigned n, void *dst, size_t out_size_w64)
{
    union {
        unsigned char buf[128];
        sph_u64 dummy;
    } u;
    size_t ptr, k;
    unsigned bit_len;
    unsigned z;
    sph_u64 th, tl;
    unsigned char *out;
    
    ptr = sc->ptr;
    bit_len = ((unsigned)ptr << 3) + n;
    z = 0x80 >> n;
    u.buf[ptr] = ((ub & -z) | z) & 0xFF;
    tl = sc->T0 + bit_len;
    th = sc->T1;
    if (ptr == 0 && n == 0) {
        sc->T0 = SPH_C64(0xFFFFFFFFFFFFFC00);
        sc->T1 = SPH_C64(0xFFFFFFFFFFFFFFFF);
    } else if (sc->T0 == 0) {
        sc->T0 = SPH_C64(0xFFFFFFFFFFFFFC00) + bit_len;
        sc->T1 = SPH_T64(sc->T1 - 1);
    } else {
        sc->T0 -= 1024 - bit_len;
    }
    if (bit_len <= 894) {
        memset(u.buf + ptr + 1, 0, 111 - ptr);
        if (out_size_w64 == 8)
            u.buf[111] |= 1;
        sph_enc64be_aligned(u.buf + 112, th);
        sph_enc64be_aligned(u.buf + 120, tl);
        blake64(sc, u.buf + ptr, 128 - ptr);
    } else {
        memset(u.buf + ptr + 1, 0, 127 - ptr);
        blake64(sc, u.buf + ptr, 128 - ptr);
        sc->T0 = SPH_C64(0xFFFFFFFFFFFFFC00);
        sc->T1 = SPH_C64(0xFFFFFFFFFFFFFFFF);
        memset(u.buf, 0, 112);
        if (out_size_w64 == 8)
            u.buf[111] = 1;
        sph_enc64be_aligned(u.buf + 112, th);
        sph_enc64be_aligned(u.buf + 120, tl);
        blake64(sc, u.buf, 128);
    }
    out = dst;
    for (k = 0; k < out_size_w64; k ++)
        sph_enc64be(out + (k << 3), sc->H[k]);
}


/* see sph_blake.h */
void
sph_blake512_init(void *cc)
{
    blake64_init(cc, blakeIV512, salt_zero_big);
}

/* see sph_blake.h */
void
sph_blake512(void *cc, const void *data, size_t len)
{
    blake64(cc, data, len);
}

/* see sph_blake.h */
void
sph_blake512_addbits_and_close(void *cc, unsigned ub, unsigned n, void *dst)
{
    blake64_close(cc, ub, n, dst, 8);
    sph_blake512_init(cc);
}

/* see sph_blake.h */
void
sph_blake512_close(void *cc, void *dst)
{
    sph_blake512_addbits_and_close(cc, 0, 0, dst);
}

#endif


