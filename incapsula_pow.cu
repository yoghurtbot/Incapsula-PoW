#include <cstdio>
#include <cstdint>
#include <cstring>
#include <climits>
#include <chrono>
#include <iostream>
#include <cuda_runtime.h>

#define SHA1_BLOCK_SIZE 20

// Constant memory declarations
__constant__ uint8_t d_salt_const[16]; // 16-byte salt for PoW
__constant__ uint32_t d_target_const[5]; // 5x32-bit words = 160-bit target hash

// Rotate left utility
// Performs bitwise left rotation on a 32-bit word
__device__ __forceinline__ uint32_t rotate_left(uint32_t value, uint32_t count) {
    return (value << count) | (value >> (32 - count));
}

// Single-block SHA-1 transform
__device__ void sha1_transform(const uint8_t* data, uint32_t* state) {
    uint32_t w[80];
    // Pepare message schedule (first 16 words from data, big-endian)
	#pragma unroll
    for (int i = 0; i < 16; ++i) {
        w[i] = (uint32_t(data[i * 4]) << 24) |
            (uint32_t(data[i * 4 + 1]) << 16) |
            (uint32_t(data[i * 4 + 2]) << 8) |
            (uint32_t(data[i * 4 + 3]));
    }
	#pragma unroll
    // Extend to 80 words
    for (int i = 16; i < 80; ++i) {
        w[i] = rotate_left(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    // Init working variables
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3], e = state[4];

    // Main loop - 80 rounds
	#pragma unroll
    for (int i = 0; i < 80; ++i) {
        uint32_t f, k;
        if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6; }
        uint32_t temp = rotate_left(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = rotate_left(b, 30);
        b = a;
        a = temp;
    }
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
}

//-----------------------------------------------------------------------------------
// CUDA kernel: pow_kernel
// Each thread tests one nonce for a SHA-1 match to the target.
// 'startNonce' + thread-index = current nonce
// 'batchSize' limits how many total nonces per kernel launch
// 'result' is a device pointer to int: stores the smallest matching nonce via atomicMin
//-----------------------------------------------------------------------------------
__global__ void pow_kernel(uint32_t startNonce, uint32_t batchSize, int* result) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= batchSize || *result != INT_MAX) return;

    uint32_t nonce = startNonce + idx;
    uint8_t message[64];
    // Build the 24-byte message: salt (16) + nonce (4 little-endian) + 4 zero bytes
	#pragma unroll
    for (int i = 0; i < 16; ++i) message[i] = d_salt_const[i];
    message[16] = uint8_t(nonce & 0xFF);
    message[17] = uint8_t((nonce >> 8) & 0xFF);
    message[18] = uint8_t((nonce >> 16) & 0xFF);
    message[19] = uint8_t((nonce >> 24) & 0xFF);

	#pragma unroll
    for (int i = 20; i < 24; ++i) {
        message[i] = 0;
    }

    // Standard SHA-1 padding: 0x80 then zeros until 56, then 64-bit length
    message[24] = 0x80;
	#pragma unroll
    for (int i = 25; i < 56; ++i) {
        message[i] = 0;
    }
    uint64_t bitLen = (uint64_t)24 * 8;

	#pragma unroll
    for (int i = 0; i < 8; ++i) message[56 + i] = uint8_t((bitLen >> ((7 - i) * 8)) & 0xFF);

    // Compute SHA-1
    uint32_t state[5] = { 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 };
    sha1_transform(message, state);

    // Compare to constant target
    bool match = true;
	#pragma unroll
    for (int i = 0; i < 5; ++i) {
        if (state[i] != d_target_const[i]) { match = false; break; }
    }

    if (match) {
        // atomically record smallest nonce that matches
        atomicMin(result, (int)nonce);
    }
}

int hexCharToInt(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}


void hexToBytes(const char* hex, uint8_t* out, size_t len) {
    for (size_t i = 0; i < len; ++i) {
        out[i] = (hexCharToInt(hex[2 * i]) << 4) |
            hexCharToInt(hex[2 * i + 1]);
    }
}

int main(int argc, char** argv) {
    if (argc != 4) {
        std::printf("Usage: %s <T_ms> <D_hex20> <S_hex16>\n", argv[0]);
        return 1;
    }
    int T = std::atoi(argv[1]);     // time limit in milliseconds
    const char* Dhex = argv[2];     // target hash in hex (20 bytes)
    const char* Shex = argv[3];     // salt in hex (16 bytes)

    uint8_t h_salt[16]; hexToBytes(Shex, h_salt, 16);
    uint8_t h_targetBytes[20]; hexToBytes(Dhex, h_targetBytes, 20);
    uint32_t h_target[5];

    for (int i = 0; i < 5; ++i) {
        h_target[i] = (uint32_t(h_targetBytes[4 * i]) << 24) |
            (uint32_t(h_targetBytes[4 * i + 1]) << 16) |
            (uint32_t(h_targetBytes[4 * i + 2]) << 8) |
            (uint32_t(h_targetBytes[4 * i + 3]));
    }


    // Copy salt & target to GPU constant memory
    cudaMemcpyToSymbol(d_salt_const, h_salt, 16);
    cudaMemcpyToSymbol(d_target_const, h_target, 5 * sizeof(uint32_t));

    int* d_result; cudaMalloc(&d_result, sizeof(int));
    int h_result = INT_MAX;
    cudaMemcpy(d_result, &h_result, sizeof(int), cudaMemcpyHostToDevice);

    // Define kernel launch parameters
    const uint32_t batchSize = 1 << 20;
    const uint32_t threadsPerBlock = 256;
    uint32_t blocks = (batchSize + threadsPerBlock - 1) / threadsPerBlock;

    uint32_t startNonce = 0;
    uint64_t totalIterations = 0;

    // Start timing and loop until nonce found or time expires
    auto t_start = std::chrono::high_resolution_clock::now();
    auto t_limit = t_start + std::chrono::milliseconds(T);
    int foundNonce = -1;

    while (std::chrono::high_resolution_clock::now() < t_limit) {
        h_result = INT_MAX;
        cudaMemcpy(d_result, &h_result, sizeof(int), cudaMemcpyHostToDevice);

        // Launch kernel batch
        pow_kernel << <blocks, threadsPerBlock >> > (startNonce, batchSize, d_result);
        cudaDeviceSynchronize();
        cudaMemcpy(&h_result, d_result, sizeof(int), cudaMemcpyDeviceToHost);
        if (h_result != INT_MAX) {
            foundNonce = h_result;
            totalIterations += uint64_t(foundNonce - startNonce) + 1;
            break;
        }

        // No match in this batch, continue
        totalIterations += batchSize;
        startNonce += batchSize;
    }

    // Timing end
    auto t_end = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(t_end - t_start).count();

    if (foundNonce >= 0) {
        std::printf("foundNonce: %d\niterations: %llu\ntimeTaken: %lld ms\n", foundNonce, totalIterations, (long long)elapsed);
    }
    else {
        std::printf("No valid nonce found in %llu iterations within %d ms\n", totalIterations, T);
    }

    cudaFree(d_result);
    return 0;
}
