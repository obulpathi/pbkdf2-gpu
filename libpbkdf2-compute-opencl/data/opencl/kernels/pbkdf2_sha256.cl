/*
 * PBKDF2-HMAC-SHA256 OpenCL kernel
 *
 * Copyright (c) 2012, Sayantan Datta <std2048 at gmail dot com>
 * Copyright (c) 2015, Ondrej Mosnacek <omosnacek@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Based on software published under the following license:
 *
 *     This software is Copyright (c) 2012 Sayantan Datta <std2048 at gmail dot com>
 *     and it is hereby released to the general public under the following terms:
 *     Redistribution and use in source and binary forms, with or without modification, are permitted.
 *     Based on S3nf implementation http://openwall.info/wiki/john/MSCash2
 *     Modified to support salts upto 19 characters. Bug in orginal code allowed only upto 8 characters.
 */

#ifdef cl_nv_pragma_unroll
#define NVIDIA
#endif /* cl_nv_pragma_unroll */

/* TODO: make optional: */
#define DEBUG_LOG

#define LENGTH_UINT(len) (len / sizeof(uint))

/* Tests depend on logging functions: */
#ifdef TESTS

#ifndef DEBUG_LOG
#define DEBUG_LOG
#endif /* DEBUG_LOG */

#ifndef ENABLE_LOGGING
#define ENABLE_LOGGING
#endif /* ENABLE_LOGGING */

#endif /* TESTS */

/* Logging functions: */
#ifdef DEBUG_LOG
#pragma OPENCL EXTENSION cl_khr_byte_addressable_store : enable

typedef struct output_stream {
    __global char *buffer;
    uint pos;
} output_stream_t;

inline void stream_init(__private output_stream_t *stream, __global char *buffer)
{
    stream->buffer = buffer;
    stream->pos = 0;
}

inline void stream_close(__private output_stream_t *stream)
{
    stream->buffer[stream->pos++] = '\0';
}

inline void dump_l(__private output_stream_t *stream, __constant char *str)
{
    while (*str != '\0') {
        stream->buffer[stream->pos++] = *str;
        ++str;
    }
}

inline void dump_s(__private output_stream_t *stream, __private char *str)
{
    while (*str != '\0') {
        stream->buffer[stream->pos++] = *str;
        ++str;
    }
}

inline void dump_ui(__private output_stream_t *stream, uint i)
{
    uint rev = 0;
    while (i != 0) {
        uint d = i / 10;
        rev *= 10;
        rev += i % 10;
        i = d;
    }
    if (rev == 0) {
        stream->buffer[stream->pos++] = '0';
    } else {
        do {
            uint d = rev / 10;
            uint r = rev % 10;
            stream->buffer[stream->pos++] = '0' + r;
            rev = d;
        } while (rev != 0);
    }
}

inline void dump_uix(__private output_stream_t *stream, uint n)
{
    for (uint i = 0; i < 8; i++) {
        uint r = (n >> (32 - ((i + 1) << 2))) & 0xf;
        stream->buffer[stream->pos++] = r < 0xa ? '0' + r : 'a' + (r - 0xa);
    }
}

inline void dump_uix_a(__private output_stream_t *stream, __private uint *array, uint length) {
    dump_l(stream, "[");
    for (uint i = 0; i < length; i++) {
        if (i > 0) { dump_l(stream, " "); }
        dump_uix(stream, array[i]);
    }
    dump_l(stream, "]");
}
#endif /* DEBUG_LOG */

/* SHA256 macros: */
#define SHA256_INIT_A                 0x6a09e667
#define SHA256_INIT_B                 0xbb67ae85
#define SHA256_INIT_C                 0x3c6ef372
#define SHA256_INIT_D                 0xa54ff53a
#define SHA256_INIT_E                 0x510e527f
#define SHA256_INIT_F                 0x9b05688c
#define SHA256_INIT_G                 0x1f83d9ab
#define SHA256_INIT_H                 0x5be0cd19

#define SHA256_UNROLL_IBLOCK(block) \
    block[0x0], block[0x1], block[0x2], block[0x3], \
    block[0x4], block[0x5], block[0x6], block[0x7], \
    block[0x8], block[0x9], block[0xA], block[0xB], \
    block[0xC], block[0xD], block[0xE], block[0xF]

#define SHA256_UNROLL_OBLOCK(block) \
    block[0x0], \
    block[0x1], \
    block[0x2], \
    block[0x3], \
    block[0x4], \
    block[0x5], \
    block[0x6], \
    block[0x7]

#define SHA256_UNROLL_INITSTATE \
    SHA256_INIT_A, \
    SHA256_INIT_B, \
    SHA256_INIT_C, \
    SHA256_INIT_D, \
    SHA256_INIT_E, \
    SHA256_INIT_F, \
    SHA256_INIT_G, \
    SHA256_INIT_H

#define ROR(x, n) rotate((uint)(x), 32 - (uint)(n))

#ifndef NVIDIA
#define SHA256_F0(x,y,z) bitselect(z, y, x)
#else
#define SHA256_F0(x,y,z) (z ^ (x & (y ^ z)))
#endif /* NVIDIA */

#define SHA256_F1(x,y,z) bitselect(y, x, y ^ z)

#define SHA256_STEP(a, b, c, d, e, f, g, h, k, x) \
do { \
    h += ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25); \
    h += SHA256_F0(e, f, g); \
    h += k; \
    h += x; \
    d += h; \
    h += ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22); \
    h += SHA256_F1(a, b, c); \
} while(0)

#define SHA256_NEXT_WORDS(buffer, W0, W1, W2, W3, W4, W5, W6, W7, W8, W9, WA, WB, WC, WD, WE, WF) \
do { \
    buffer[0x0] = W0 + (ROR(W1,          7) ^ ROR(W1,          18) ^ (W1          >> 3)) + W9          + (ROR(WE,          17) ^ ROR(WE,          19) ^ (WE          >> 10)); \
    buffer[0x1] = W1 + (ROR(W2,          7) ^ ROR(W2,          18) ^ (W2          >> 3)) + WA          + (ROR(WF,          17) ^ ROR(WF,          19) ^ (WF          >> 10)); \
    buffer[0x2] = W2 + (ROR(W3,          7) ^ ROR(W3,          18) ^ (W3          >> 3)) + WB          + (ROR(buffer[0x0], 17) ^ ROR(buffer[0x0], 19) ^ (buffer[0x0] >> 10)); \
    buffer[0x3] = W3 + (ROR(W4,          7) ^ ROR(W4,          18) ^ (W4          >> 3)) + WC          + (ROR(buffer[0x1], 17) ^ ROR(buffer[0x1], 19) ^ (buffer[0x1] >> 10)); \
    buffer[0x4] = W4 + (ROR(W5,          7) ^ ROR(W5,          18) ^ (W5          >> 3)) + WD          + (ROR(buffer[0x2], 17) ^ ROR(buffer[0x2], 19) ^ (buffer[0x2] >> 10)); \
    buffer[0x5] = W5 + (ROR(W6,          7) ^ ROR(W6,          18) ^ (W6          >> 3)) + WE          + (ROR(buffer[0x3], 17) ^ ROR(buffer[0x3], 19) ^ (buffer[0x3] >> 10)); \
    buffer[0x6] = W6 + (ROR(W7,          7) ^ ROR(W7,          18) ^ (W7          >> 3)) + WF          + (ROR(buffer[0x4], 17) ^ ROR(buffer[0x4], 19) ^ (buffer[0x4] >> 10)); \
    buffer[0x7] = W7 + (ROR(W8,          7) ^ ROR(W8,          18) ^ (W8          >> 3)) + buffer[0x0] + (ROR(buffer[0x5], 17) ^ ROR(buffer[0x5], 19) ^ (buffer[0x5] >> 10)); \
    buffer[0x8] = W8 + (ROR(W9,          7) ^ ROR(W9,          18) ^ (W9          >> 3)) + buffer[0x1] + (ROR(buffer[0x6], 17) ^ ROR(buffer[0x6], 19) ^ (buffer[0x6] >> 10)); \
    buffer[0x9] = W9 + (ROR(WA,          7) ^ ROR(WA,          18) ^ (WA          >> 3)) + buffer[0x2] + (ROR(buffer[0x7], 17) ^ ROR(buffer[0x7], 19) ^ (buffer[0x7] >> 10)); \
    buffer[0xA] = WA + (ROR(WB,          7) ^ ROR(WB,          18) ^ (WB          >> 3)) + buffer[0x3] + (ROR(buffer[0x8], 17) ^ ROR(buffer[0x8], 19) ^ (buffer[0x8] >> 10)); \
    buffer[0xB] = WB + (ROR(WC,          7) ^ ROR(WC,          18) ^ (WC          >> 3)) + buffer[0x4] + (ROR(buffer[0x9], 17) ^ ROR(buffer[0x9], 19) ^ (buffer[0x9] >> 10)); \
    buffer[0xC] = WC + (ROR(WD,          7) ^ ROR(WD,          18) ^ (WD          >> 3)) + buffer[0x5] + (ROR(buffer[0xA], 17) ^ ROR(buffer[0xA], 19) ^ (buffer[0xA] >> 10)); \
    buffer[0xD] = WD + (ROR(WE,          7) ^ ROR(WE,          18) ^ (WE          >> 3)) + buffer[0x6] + (ROR(buffer[0xB], 17) ^ ROR(buffer[0xB], 19) ^ (buffer[0xB] >> 10)); \
    buffer[0xE] = WE + (ROR(WF,          7) ^ ROR(WF,          18) ^ (WF          >> 3)) + buffer[0x7] + (ROR(buffer[0xC], 17) ^ ROR(buffer[0xC], 19) ^ (buffer[0xC] >> 10)); \
    buffer[0xF] = WF + (ROR(buffer[0x0], 7) ^ ROR(buffer[0x0], 18) ^ (buffer[0x0] >> 3)) + buffer[0x8] + (ROR(buffer[0xD], 17) ^ ROR(buffer[0xD], 19) ^ (buffer[0xD] >> 10)); \
} while(0)

#define SHA256_K00 0x428a2f98
#define SHA256_K01 0x71374491
#define SHA256_K02 0xb5c0fbcf
#define SHA256_K03 0xe9b5dba5
#define SHA256_K04 0x3956c25b
#define SHA256_K05 0x59f111f1
#define SHA256_K06 0x923f82a4
#define SHA256_K07 0xab1c5ed5
#define SHA256_K08 0xd807aa98
#define SHA256_K09 0x12835b01
#define SHA256_K0A 0x243185be
#define SHA256_K0B 0x550c7dc3
#define SHA256_K0C 0x72be5d74
#define SHA256_K0D 0x80deb1fe
#define SHA256_K0E 0x9bdc06a7
#define SHA256_K0F 0xc19bf174
#define SHA256_K10 0xe49b69c1
#define SHA256_K11 0xefbe4786
#define SHA256_K12 0x0fc19dc6
#define SHA256_K13 0x240ca1cc
#define SHA256_K14 0x2de92c6f
#define SHA256_K15 0x4a7484aa
#define SHA256_K16 0x5cb0a9dc
#define SHA256_K17 0x76f988da
#define SHA256_K18 0x983e5152
#define SHA256_K19 0xa831c66d
#define SHA256_K1A 0xb00327c8
#define SHA256_K1B 0xbf597fc7
#define SHA256_K1C 0xc6e00bf3
#define SHA256_K1D 0xd5a79147
#define SHA256_K1E 0x06ca6351
#define SHA256_K1F 0x14292967
#define SHA256_K20 0x27b70a85
#define SHA256_K21 0x2e1b2138
#define SHA256_K22 0x4d2c6dfc
#define SHA256_K23 0x53380d13
#define SHA256_K24 0x650a7354
#define SHA256_K25 0x766a0abb
#define SHA256_K26 0x81c2c92e
#define SHA256_K27 0x92722c85
#define SHA256_K28 0xa2bfe8a1
#define SHA256_K29 0xa81a664b
#define SHA256_K2A 0xc24b8b70
#define SHA256_K2B 0xc76c51a3
#define SHA256_K2C 0xd192e819
#define SHA256_K2D 0xd6990624
#define SHA256_K2E 0xf40e3585
#define SHA256_K2F 0x106aa070
#define SHA256_K30 0x19a4c116
#define SHA256_K31 0x1e376c08
#define SHA256_K32 0x2748774c
#define SHA256_K33 0x34b0bcb5
#define SHA256_K34 0x391c0cb3
#define SHA256_K35 0x4ed8aa4a
#define SHA256_K36 0x5b9cca4f
#define SHA256_K37 0x682e6ff3
#define SHA256_K38 0x748f82ee
#define SHA256_K39 0x78a5636f
#define SHA256_K3A 0x84c87814
#define SHA256_K3B 0x8cc70208
#define SHA256_K3C 0x90befffa
#define SHA256_K3D 0xa4506ceb
#define SHA256_K3E 0xbef9a3f7
#define SHA256_K3F 0xc67178f2

#define SHA256(A, B, C, D, E, F, G, H, buffer, W0, W1, W2, W3, W4, W5, W6, W7, W8, W9, WA, WB, WC, WD, WE, WF) \
do { \
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K00, W0); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K01, W1); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K02, W2); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K03, W3); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K04, W4); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K05, W5); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K06, W6); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K07, W7); \
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K08, W8); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K09, W9); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K0A, WA); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K0B, WB); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K0C, WC); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K0D, WD); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K0E, WE); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K0F, WF); \
\
    SHA256_NEXT_WORDS(buffer, \
        W0, W1, W2, W3, W4, W5, W6, W7, \
        W8, W9, WA, WB, WC, WD, WE, WF); \
\
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K10, buffer[0x0]); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K11, buffer[0x1]); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K12, buffer[0x2]); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K13, buffer[0x3]); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K14, buffer[0x4]); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K15, buffer[0x5]); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K16, buffer[0x6]); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K17, buffer[0x7]); \
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K18, buffer[0x8]); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K19, buffer[0x9]); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K1A, buffer[0xA]); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K1B, buffer[0xB]); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K1C, buffer[0xC]); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K1D, buffer[0xD]); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K1E, buffer[0xE]); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K1F, buffer[0xF]); \
\
    SHA256_NEXT_WORDS(buffer, \
        buffer[0x0], buffer[0x1], buffer[0x2], buffer[0x3], \
        buffer[0x4], buffer[0x5], buffer[0x6], buffer[0x7], \
        buffer[0x8], buffer[0x9], buffer[0xA], buffer[0xB], \
        buffer[0xC], buffer[0xD], buffer[0xE], buffer[0xF]); \
\
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K20, buffer[0x0]); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K21, buffer[0x1]); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K22, buffer[0x2]); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K23, buffer[0x3]); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K24, buffer[0x4]); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K25, buffer[0x5]); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K26, buffer[0x6]); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K27, buffer[0x7]); \
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K28, buffer[0x8]); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K29, buffer[0x9]); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K2A, buffer[0xA]); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K2B, buffer[0xB]); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K2C, buffer[0xC]); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K2D, buffer[0xD]); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K2E, buffer[0xE]); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K2F, buffer[0xF]); \
\
    SHA256_NEXT_WORDS(buffer, \
        buffer[0x0], buffer[0x1], buffer[0x2], buffer[0x3], \
        buffer[0x4], buffer[0x5], buffer[0x6], buffer[0x7], \
        buffer[0x8], buffer[0x9], buffer[0xA], buffer[0xB], \
        buffer[0xC], buffer[0xD], buffer[0xE], buffer[0xF]); \
\
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K30, buffer[0x0]); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K31, buffer[0x1]); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K32, buffer[0x2]); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K33, buffer[0x3]); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K34, buffer[0x4]); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K35, buffer[0x5]); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K36, buffer[0x6]); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K37, buffer[0x7]); \
    SHA256_STEP(A, B, C, D, E, F, G, H, SHA256_K38, buffer[0x8]); \
    SHA256_STEP(H, A, B, C, D, E, F, G, SHA256_K39, buffer[0x9]); \
    SHA256_STEP(G, H, A, B, C, D, E, F, SHA256_K3A, buffer[0xA]); \
    SHA256_STEP(F, G, H, A, B, C, D, E, SHA256_K3B, buffer[0xB]); \
    SHA256_STEP(E, F, G, H, A, B, C, D, SHA256_K3C, buffer[0xC]); \
    SHA256_STEP(D, E, F, G, H, A, B, C, SHA256_K3D, buffer[0xD]); \
    SHA256_STEP(C, D, E, F, G, H, A, B, SHA256_K3E, buffer[0xE]); \
    SHA256_STEP(B, C, D, E, F, G, H, A, SHA256_K3F, buffer[0xF]); \
} while(0)

/* SHA256 block sizes: */
#define INPUT_BLOCK_LENGTH 64
#define OUTPUT_BLOCK_LENGTH 32

inline void sha256_update_block(
    uint prev_A, uint prev_B, uint prev_C, uint prev_D,
    uint prev_E, uint prev_F, uint prev_G, uint prev_H,
    __private uint *block, __private uint *state)
{
    state[0] = prev_A;
    state[1] = prev_B;
    state[2] = prev_C;
    state[3] = prev_D;
    state[4] = prev_E;
    state[5] = prev_F;
    state[6] = prev_G;
    state[7] = prev_H;

    SHA256(
        state[0], state[1], state[2], state[3],
        state[4], state[5], state[6], state[7],
        block,
        block[0x0], block[0x1], block[0x2], block[0x3],
        block[0x4], block[0x5], block[0x6], block[0x7],
        block[0x8], block[0x9], block[0xA], block[0xB],
        block[0xC], block[0xD], block[0xE], block[0xF]
    );

    state[0] += prev_A;
    state[1] += prev_B;
    state[2] += prev_C;
    state[3] += prev_D;
    state[4] += prev_E;
    state[5] += prev_F;
    state[6] += prev_G;
    state[7] += prev_H;
}

inline void sha256_digest_digest(
    uint prev_A, uint prev_B, uint prev_C, uint prev_D,
    uint prev_E, uint prev_F, uint prev_G, uint prev_H,
    __private uint *buffer, __private uint *state)
{
    state[0] = prev_A;
    state[1] = prev_B;
    state[2] = prev_C;
    state[3] = prev_D;
    state[4] = prev_E;
    state[5] = prev_F;
    state[6] = prev_G;
    state[7] = prev_H;

    SHA256(
        state[0], state[1], state[2], state[3],
        state[4], state[5], state[6], state[7],
        buffer,
        buffer[0], buffer[1], buffer[2], buffer[3],
        buffer[4], buffer[5], buffer[6], buffer[7],
        0x80000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000300
    );

    state[0] += prev_A;
    state[1] += prev_B;
    state[2] += prev_C;
    state[3] += prev_D;
    state[4] += prev_E;
    state[5] += prev_F;
    state[6] += prev_G;
    state[7] += prev_H;
}

#ifdef DEBUG_LOG
inline void dump_sha256(__private output_stream_t *out, __private uint *hash)
{
    dump_l(out, "SHA256");
    dump_uix_a(out, hash, LENGTH_UINT(OUTPUT_BLOCK_LENGTH));
}
#endif /* DEBUG_LOG */

/* PBKDF2 functions: */
#ifndef SALT_LENGTH
#error "SALT_LENGTH not defined!"
#endif /* SALT_LENGTH */

#define SWITCH_ENDIANNESS(v) (\
    (((uint)(v) & 0xff) << 24) | \
    (((uint)(v) <<  8) & 0x00ff0000) | \
    (((uint)(v) >>  8) & 0x0000ff00) | \
    (((uint)(v) >> 24) & 0x000000ff))

inline void pbkdf2_init(
    __private output_stream_t *dbg,
    __constant uint *salt, uint dk_block_index,
    const __private uint *istate,
    __private uint *state)
{
    const __private uint *prev_state = istate;

    /* Process contigous blocks of salt: */
    {
        uint buffer[LENGTH_UINT(INPUT_BLOCK_LENGTH)];
        for (uint i = 0; i < SALT_LENGTH / INPUT_BLOCK_LENGTH; i++) {
            for (uint k = 0; k < LENGTH_UINT(INPUT_BLOCK_LENGTH); k++) {
                buffer[k] = SWITCH_ENDIANNESS(salt[k]);
            }
            sha256_update_block(SHA256_UNROLL_OBLOCK(prev_state), buffer, state);
            salt += LENGTH_UINT(INPUT_BLOCK_LENGTH);
            prev_state = state;
        }
    }

    /* Prepare and process the last (possibly partial) block of salt with the padding: */
    /* (may be one or two blocks) */
#define TAIL_BLOCKS ((SALT_LENGTH % INPUT_BLOCK_LENGTH) / (INPUT_BLOCK_LENGTH - 4 - 8) + 1)
    {
        uint tail[TAIL_BLOCKS * LENGTH_UINT(INPUT_BLOCK_LENGTH)];
        {
            uint i = 0;
            /* Process the rest of the salt: */
            /* (except the last (SALT_LENGTH % 4) bytes) */
            for (; i < LENGTH_UINT(SALT_LENGTH % INPUT_BLOCK_LENGTH); i++) {
                tail[i] = SWITCH_ENDIANNESS(salt[i]);
            }

            /* Append DK block index: */
            if ((SALT_LENGTH % 4) == 0) {
                tail[i] = dk_block_index + 1;
                i++;
                tail[i] = 0x80000000;
                i++;
            } else {
                tail[i] = SWITCH_ENDIANNESS(salt[i]) | ((dk_block_index + 1) >> ((SALT_LENGTH % 4) << 3));
                i++;
                tail[i] = ((dk_block_index + 1) << (32 - ((SALT_LENGTH % 4) << 3))) | ((uint)0x80000000 >> ((SALT_LENGTH % 4) << 3));
                i++;
            }

            /* Pad with zeroes: */
            for (; i < TAIL_BLOCKS * LENGTH_UINT(INPUT_BLOCK_LENGTH) - 1; i++) {
                tail[i] = 0x00000000;
            }

            /* Put SHA256 message length at the end of the last block: */
            tail[TAIL_BLOCKS * LENGTH_UINT(INPUT_BLOCK_LENGTH) - 1] = (INPUT_BLOCK_LENGTH + SALT_LENGTH + 4) * 8;
        }

#ifdef ENABLE_LOGGING
    dump_l(dbg, "Tail: ");
    dump_uix_a(dbg, tail, TAIL_BLOCKS * LENGTH_UINT(INPUT_BLOCK_LENGTH));
    dump_l(dbg, "\n");
#endif /* ENABLE_LOGGING */

        /* Process the prepared blocks: */
        __private uint *input = tail;
        for (uint i = 0; i < TAIL_BLOCKS; i++) {
            sha256_update_block(SHA256_UNROLL_OBLOCK(prev_state), input, state);
            input += LENGTH_UINT(INPUT_BLOCK_LENGTH);
            prev_state = state;
        }
        /* From now on 'prev_state' definitely refers to 'state' */
        /* which contains the half-done HMAC of iteration 0.     */
    }
#undef TAIL_BLOCKS

#ifdef ENABLE_LOGGING
    dump_l(dbg, "Iteration 0 semi-digest: ");
    dump_sha256(dbg, state);
    dump_l(dbg, "\n");
#endif /* ENABLE_LOGGING */
}

inline void pbkdf2_iter(
    __private output_stream_t *dbg,
    const __private uint *istate, const __private uint *ostate,
    uint iterations,
    __private uint *dk, __private uint *state)
{
    uint buffer[LENGTH_UINT(INPUT_BLOCK_LENGTH)];

    /* Complete the HMAC of the first iteration: */
    sha256_digest_digest(SHA256_UNROLL_OBLOCK(ostate), state, buffer);

#ifdef ENABLE_LOGGING
    dump_l(dbg, "Iteration 0 digest: ");
    dump_sha256(dbg, buffer);
    dump_l(dbg, "\n");
#endif /* ENABLE_LOGGING */

    /* Copy the result of iteration 0 to the final result buffer: */
    for (uint i = 0; i < LENGTH_UINT(OUTPUT_BLOCK_LENGTH); i++) {
        dk[i] = buffer[i];
    }

    /* Perform the remaining iterations: */
    for (uint i = 1; i < iterations; i++) {
        sha256_digest_digest(SHA256_UNROLL_OBLOCK(istate), buffer, state);

#ifdef ENABLE_LOGGING
        dump_l(dbg, "Iteration ");
        dump_ui(dbg, i);
        dump_l(dbg, " semi-digest: ");
        dump_sha256(dbg, state);
        dump_l(dbg, "\n");
#endif /* ENABLE_LOGGING */

        sha256_digest_digest(SHA256_UNROLL_OBLOCK(ostate), state, buffer);

#ifdef ENABLE_LOGGING
        dump_l(dbg, "Iteration ");
        dump_ui(dbg, i);
        dump_l(dbg, " digest: ");
        dump_sha256(dbg, buffer);
        dump_l(dbg, "\n");
#endif /* ENABLE_LOGGING */

        /* XOR the result of this iteration into the final result: */
        for (uint i = 0; i < LENGTH_UINT(OUTPUT_BLOCK_LENGTH); i++) {
            dk[i] ^= buffer[i];
        }

#ifdef ENABLE_LOGGING
        dump_l(dbg, "Iteration ");
        dump_ui(dbg, i);
        dump_l(dbg, " digest XOR'd: ");
        dump_sha256(dbg, dk);
        dump_l(dbg, "\n");
#endif /* ENABLE_LOGGING */
    }
}

/* Main kernel: */
__kernel
void pbkdf2_kernel(
    const __global uint *input,
    __global uint *output,
    __constant uint *salt,
    uint dk_blocks,
    uint iterations,
    uint batchSize,
    __global char *debug_buffer)
{
#ifdef DEBUG_LOG
    output_stream_t dbg;
    stream_init(&dbg, debug_buffer);
#endif /* DEBUG_LOG */

    uint input_block_index = (uint)get_global_id(0);
    uint input_pos = input_block_index;

    uint ipad_state[LENGTH_UINT(OUTPUT_BLOCK_LENGTH)];
    uint opad_state[LENGTH_UINT(OUTPUT_BLOCK_LENGTH)];
    {
        uint ipad[LENGTH_UINT(INPUT_BLOCK_LENGTH)];
        uint opad[LENGTH_UINT(INPUT_BLOCK_LENGTH)];

        for (uint row = 0; row < LENGTH_UINT(INPUT_BLOCK_LENGTH); row++) {
            uint in = SWITCH_ENDIANNESS(input[input_pos + row * batchSize]);

#ifdef ENABLE_LOGGING
            dump_uix(&dbg, in);
            dump_l(&dbg, " ");
#endif /* ENABLE_LOGGING */

            ipad[row] = in ^ 0x36363636;
            opad[row] = in ^ 0x5C5C5C5C;
        }
#ifdef ENABLE_LOGGING
        dump_l(&dbg, "\n");
#endif /* ENABLE_LOGGING */

        sha256_update_block(SHA256_UNROLL_INITSTATE, ipad, ipad_state);
        sha256_update_block(SHA256_UNROLL_INITSTATE, opad, opad_state);
    }

    uint dk_block_index = (uint)get_global_id(1);

    uint buffer[LENGTH_UINT(INPUT_BLOCK_LENGTH)];
    pbkdf2_init(&dbg, salt, dk_block_index, ipad_state, buffer);

    uint dk[LENGTH_UINT(OUTPUT_BLOCK_LENGTH)];
    pbkdf2_iter(&dbg, ipad_state, opad_state, iterations, dk, buffer);

    uint output_block_index = input_block_index * dk_blocks + dk_block_index;
    uint output_pos = output_block_index;

    for (uint i = 0; i < LENGTH_UINT(OUTPUT_BLOCK_LENGTH); i++) {
        output[output_pos + i * batchSize * dk_blocks] = SWITCH_ENDIANNESS(dk[i]);
    }

#ifdef DEBUG_LOG
    stream_close(&dbg);
#endif /* DEBUG_LOG */
}

/* Testing functions & testing kernel: */
#ifdef TESTS
inline bool sha256_compare(__private uint *hash1, __private uint *hash2)
{
    for (uint i = 0; i < LENGTH_UINT(OUTPUT_BLOCK_LENGTH); i++) {
        if (hash1[i] != hash2[i]) {
            return false;
        }
    }
    return true;
}

inline void test_sha256(__private output_stream_t *out, __constant char *name,
    __private uint *block, __private uint *hash)
{
    uint state[LENGTH_UINT(OUTPUT_BLOCK_LENGTH)];
    sha256_update_block(SHA256_UNROLL_INITSTATE, block, state);
    if (!sha256_compare(hash, state)) {
        dump_l(out, "SHA256 test '");
        dump_l(out, name);
        dump_l(out, "' failed! ");
        dump_sha256(out, state);
        dump_l(out, " should be ");
        dump_sha256(out, hash);
        dump_l(out, "\n");
    }
}

__kernel
void run_tests(__global char *debug_buffer)
{
    output_stream_t out;
    out.buffer = debug_buffer;
    out.pos = 0;

    {
        if (SWITCH_ENDIANNESS(0x12345678) != 0x78563412) {
            dump_l(&out, "SWAP_ENDIANNESS(0x12345678) should be 0x78563412\n");
        }
        if (SWITCH_ENDIANNESS(0x78563412) != 0x12345678) {
            dump_l(&out, "SWAP_ENDIANNESS(0x78563412) should be 0x12345678\n");
        }
    }
    // TODO Make SHA-256 tests
    {
        uint tv_i[] = {
            0x80000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
        };
        uint tv_o[] = {
            0xda39a3ee, 0x5e6b4b0d, 0x3255bfef, 0x95601890, 0xafd80709,
        };
        test_sha256(&out, "", tv_i, tv_o);
    }
    {
        uint tv_i[] = {
            0x61626380, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000018,
        };
        uint tv_o[] = {
            0xa9993e36, 0x4706816a, 0xba3e2571, 0x7850c26c, 0x9cd0d89d,
        };
        test_sha256(&out, "abc", tv_i, tv_o);
    }

    stream_close(&out);
}
#endif /* TESTS */
