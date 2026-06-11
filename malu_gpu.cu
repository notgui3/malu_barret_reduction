#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <openssl/bn.h>
#include <stdbool.h>

#include <cuda_runtime.h>



// Most functions use a pointer for output, returns 1 if function succeeded, 0 if not


// GPU cannot use malloc as they are tooo slow, so we used fixed size
typedef struct {
    uint64_t nums[128]; // 128 make sure no overflow
    uint64_t size;
} LN;


// static int hex_char_to_val(char c) {

//     if(c >= '0' && c <= '9'){
//         return c - '0';
//     }

//     if(c >= 'a' && c <= 'f'){
//         return 10 + (c - 'a');
//     }

//     if(c >= 'A' && c <= 'F') 
//     {return 10 + (c - 'A');
//     }
//     return -1;
// }

// int hex_to_large_num(LN *large_num, const char *str) {
//     if(large_num == NULL || str == NULL) return 0;

//     // Parse out hex prefix
//     if(str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
//         str += 2;
//     }

//     //Skip leading zeros
//     while(*str == '0') {
//         str++;
//     }

//     uint64_t len = strlen(str);
    
//     //Initialize as 0 if length was 0
//     if(len == 0) {
//         large_num->nums = (uint64_t *)calloc(1, sizeof(uint64_t));
//         if(large_num->nums == NULL) return 0;
//         large_num->size = 1;
//         return 1;
//     }

//     // Find number of uint64_t needed
//     uint64_t calculated_size = (len + 15) / 16;

//     // Allocate mem
//     large_num->nums = (uint64_t *)calloc(calculated_size, sizeof(uint64_t));
//     if(large_num->nums == NULL){
//         return 0;
//     } 
//     large_num->size = calculated_size;

//     uint64_t current_limb = 0;
//     int shift_amount = 0;
//     uint64_t accumulated_value = 0;

//     // Process from right to left, little endian, LSB at index 0
//     for (uint64_t i = len; i > 0; i--) {
//         char c = str[i - 1];
//         int val = hex_char_to_val(c);
        
//         if(val < 0) {
//             free(large_num->nums);
//             large_num->nums = NULL;
//             large_num->size = 0;
//             return 0;
//         }

//         accumulated_value |= ((uint64_t)val << shift_amount);
//         shift_amount += 4;

//         if(shift_amount == 64 || i == 1) {
//             large_num->nums[current_limb] = accumulated_value;
//             current_limb++;
//             accumulated_value = 0;
//             shift_amount = 0;
//         }
//     }

//     return 1;
// }

__host__ __device__ int LN_R_shift(LN *in, uint32_t shift_amount, LN *out){

    if(!in || !out) {
        return 0;
    }
    
    uint32_t limb_shift = shift_amount / 64;
    uint32_t bit_shift = shift_amount % 64;

    // If we shift right by more limbs than we have, the result is 0
    if(limb_shift >= in->size) {
        out->size = 1;
        out->nums[0] = 0;
        return 1;
    }

    out->size = in->size - limb_shift;
    for (uint64_t i = 0; i < out->size; i++) {
        out->nums[i] = 0;
    }

    if(bit_shift == 0){
        for (uint64_t i = 0; i < out->size; i++) {
            out->nums[i] = in->nums[i + limb_shift];
        }
    }
    else{
        uint64_t carry = 0;
        // Process from MSB to LSB
        for(int64_t i = out->size - 1; i >= 0; i--){ 
            uint64_t current = in->nums[i + limb_shift];
            out->nums[i] = (current >> bit_shift) | carry;
            carry = current << (64 - bit_shift);
        }
    }

    // Remove leading zero limbs
    while(out->size > 1 && out->nums[out->size - 1] == 0) {
        out->size--;
    }
    return 1;
}

__host__ __device__ int LN_L_shift(LN *in, uint32_t shift_amount, LN *out){

    if(!in || !out){
      return 0;
    } 
    
    uint32_t limb_shift = shift_amount / 64;
    uint32_t bit_shift = shift_amount % 64;

    // Max possible new size: current size + full limb shifts + 1 for overflow bits
    out->size = in->size + limb_shift + (bit_shift > 0 ? 1 : 0);

    if(out->size > 128){
      return 0;
    }

    for (uint64_t i = 0; i < out->size; i++) {
        out->nums[i] = 0;
    }

    if(bit_shift == 0) {
        // Perfect limb alignment
        for (uint64_t i = 0; i < in->size; i++) {
            out->nums[i + limb_shift] = in->nums[i];
        }
    } else {
        // Shift with carry
        uint64_t carry = 0;
        for (uint64_t i = 0; i < in->size; i++) {
            out->nums[i + limb_shift] = (in->nums[i] << bit_shift) | carry;
            carry = in->nums[i] >> (64 - bit_shift);
        }
        if(carry > 0) {
            out->nums[in->size + limb_shift] = carry;
        }
    }

    // Remove leading zero limbs
    while(out->size > 1 && out->nums[out->size - 1] == 0) {
        out->size--;
    }
    return 1;

}

// LN * Integer
__host__ __device__ int LN_int_mult(LN *op1, uint64_t op2, LN *out) {

    if(!op1 || !out) {
        return 0;
    }
    
    out->size = op1->size + 1; // Max possible size
    if (out->size > 128) {
        return 0;
    }

    for (uint64_t i = 0; i < out->size; i++) {
        out->nums[i] = 0;
    }

    unsigned __int128 carry = 0;

    for (uint64_t i = 0; i < op1->size; i++){
        unsigned __int128 res = (unsigned __int128)op1->nums[i] * op2 + carry;
        out->nums[i] = (uint64_t)res; // Keep lower 64 bits
        carry = res >> 64;            // Carry upper 64 bits
    }

    out->nums[op1->size] = (uint64_t)carry;

    while(out->size > 1 && out->nums[out->size - 1] == 0){
        out->size--;
    } 
    return 1;
}

// LN * LN
__host__ __device__ int LN_LN_mult(LN *op1, LN *op2, LN *out) {

    if(!op1 || !op2 || !out){
        return 0;
    }

    out->size = op1->size + op2->size;
    if (out->size > 128) {
        return 0;
    }

    for (uint64_t i = 0; i < out->size; i++) {
        out->nums[i] = 0;
    }

    for(uint64_t i = 0; i < op1->size; i++) {
        unsigned __int128 carry = 0;
        for (uint64_t j = 0; j < op2->size; j++) {
            // Multiply limbs, add existing value in out->nums, add carry
            unsigned __int128 res = (unsigned __int128)op1->nums[i] * op2->nums[j] + out->nums[i + j] + carry;
            out->nums[i + j] = (uint64_t)res;
            carry = res >> 64;
        }
        out->nums[i + op2->size] += (uint64_t)carry;
    }

    while(out->size > 1 && out->nums[out->size - 1] == 0){
        out->size--;
    }

    return 1;
}


// Compares two LNs
// Returns 1 if op1 > op2, -1 if op1 < op2, 0 if equal
__host__ __device__ int LN_cmp(const LN *op1, const LN *op2) {
    if(op1->size > op2->size) return 1;
    if(op1->size < op2->size) return -1;
    
    // Sizes are equal, compare from MSB down to LSB
    for (int64_t i = op1->size - 1; i >= 0; i--) {
        if(op1->nums[i] > op2->nums[i]) return 1;
        if(op1->nums[i] < op2->nums[i]) return -1;
    }
    return 0;
}

// Subtract, out = op1 - op2, assuming op1 > op2
__host__ __device__ int LN_sub(const LN *op1, const LN *op2, LN *out) {
    if(LN_cmp(op1, op2) < 0){
        return 0;
    }

    out->size = op1->size;

    if (out->size > 128) {
        return 0;
    }

    for (uint64_t i = 0; i < out->size; i++) {
        out->nums[i] = 0;
    }

    uint64_t borrow = 0;
    for (uint64_t i = 0; i < op1->size; i++) {
        uint64_t sub = (i < op2->size) ? op2->nums[i] : 0;
        
        uint64_t diff = op1->nums[i] - sub - borrow;
        
        // If diff > op1->nums[i], an underflow occurred, meaning we need to borrow
        if(op1->nums[i] < sub || op1->nums[i] - sub < borrow) {
            borrow = 1;
        } else {
            borrow = 0;
        }
        out->nums[i] = diff;
    }

    // Normalize (remove leading zeros)
    while(out->size > 1 && out->nums[out->size - 1] == 0) {
        out->size--;
    }

    return 1;
}


// Total number of significant bits in the LN
__host__ __device__ uint64_t LN_bit_length(const LN *num) {

    if(num->size == 0 || (num->size == 1 && num->nums[0] == 0)){
        return 0;
    }

    uint64_t msb_limb = num->nums[num->size - 1];
    uint64_t bits = (num->size - 1) * 64;

    while(msb_limb > 0) {
        bits++;
        msb_limb >>= 1;
    }

    return bits;
}

// Get a specific bit (0-indexed)
__host__ __device__ int LN_get_bit(const LN *num, uint64_t bit_index) {
    uint64_t limb = bit_index / 64;

    if(limb >= num->size){
        return 0;
    }

    return (num->nums[limb] >> (bit_index % 64)) & 1;
}

// Helper to set a specific bit in a limb to 1
__host__ __device__ void LN_set_bit(LN *num, uint64_t bit_index) {
    uint64_t limb = bit_index / 64;

    if(limb < num->size) {
        num->nums[limb] |= (1ULL << (bit_index % 64));
    }
}

// Standard Division (Shift_Subtract)
__device__ int LN_div_mod(const LN *numer, const LN *denom, LN *quotient, LN *remainder) {
    // Div by zero case
    if(denom->size == 1 && denom->nums[0] == 0) {
        return 0; 
    }
    

    // Initialize quotient and remainder to 0
    quotient->size = numer->size;
    if (quotient->size > 128) {
        return 0;
    }

    for (uint64_t i = 0; i < quotient->size; i++) {
        quotient->nums[i] = 0;
    }    
    remainder->size = 1;
    remainder->nums[0] = 0;

    uint64_t total_bits = LN_bit_length(numer);

    // Process from MSB down to LSB
    for (int64_t i = total_bits - 1; i >= 0; i--) {
        // remainder = remainder << 1
        LN temp_rem;
        LN_L_shift(remainder, 1, &temp_rem);
        *remainder = temp_rem;

        // remainder[0] = numer[i]
        remainder->nums[0] |= LN_get_bit(numer, i);

        // if remainder >= denom
        if(LN_cmp(remainder, denom) >= 0) {
            // remainder = remainder - denom
            LN new_rem;
            LN_sub(remainder, denom, &new_rem);
            *remainder = new_rem;
            
            // quotient[i] = 1
            LN_set_bit(quotient, i);
        }
    }

    // Normalize quotient
    while(quotient->size > 1 && quotient->nums[quotient->size - 1] == 0){
        quotient->size--;
    } 
    
    return 1;
}


typedef struct {
    LN M;       // The modulus
    LN mu;      // The precomputed inverse: floor(2^(2k) / M)
    uint64_t k; // Bit length of M
} LN_BarrettSet;

// Barrett Reduction Mod, out = X mod M
__device__ int LN_barrett_redu(LN *X, const LN_BarrettSet *ctx, LN *out) {
    if(!X || !ctx || !out){
        return 0;
    }

    LN q1, q2, q3, q3_M, R;
    
    // clear stack-allocated structures
    q1.size = q2.size = q3.size = q3_M.size = R.size = 1;
    q1.nums[0] = q2.nums[0] = q3.nums[0] = q3_M.nums[0] = R.nums[0] = 0;

    // q1 = X >> (k - 1)
    if(ctx->k > 1) {
        LN_R_shift(X, ctx->k - 1, &q1);
    } else {
        q1.size = X->size;
        for (uint64_t i = 0; i < q1.size; i++) {
            q1.nums[i] = X->nums[i];
        }
    }

    // q2 = q1 * mu
    LN_LN_mult(&q1, (LN*)&(ctx->mu), &q2);

    // q3 = q2 >> (k + 1)
    LN_R_shift(&q2, ctx->k + 1, &q3);

    // q3_M = q3 * M
    LN_LN_mult(&q3, (LN*)&(ctx->M), &q3_M);

    // R = X - q3_M
    if(LN_cmp(X, &q3_M) >= 0) {
        LN_sub(X, &q3_M, &R);
    } else {
        // Estimation Overshooting Fallback
        R.size = X->size;
        for (uint64_t i = 0; i < R.size; i++) {
            R.nums[i] = X->nums[i];
        }
    }

    // Corrections: while R >= M, R = R - M
    while(LN_cmp(&R, &(ctx->M)) >= 0) {
        LN temp_R;
        LN_sub(&R, &(ctx->M), &temp_R);
        R = temp_R;
    }

    // Transfer memory and values to output
    *out = R;


    return 1;
}

// Mod Expoenetation, Square Multiply, out = (base ^ exp) mod M
__device__ int LN_mod_exp(LN *base, LN *exp, LN_BarrettSet *ctx, LN *out) {

    if(!base || !exp || !ctx || !out){
        return 0;
    }

    // Set base result to 1
    LN result;
    result.size = 1;
    result.nums[0] = 1;
    for (uint64_t i = 1; i < 128; i++) {
        result.nums[i] = 0;
    }

    // base_temp = base mod M
    LN base_temp;
    base_temp.size = 1;
    base_temp.nums[0] = 0;
    for (uint64_t k = 1; k < 128; k++) {
        base_temp.nums[k] = 0;
    }
    LN_barrett_redu(base, ctx, &base_temp); 

    uint64_t total_bits = LN_bit_length(exp);

    // Process from LSB to MSB
    for (uint64_t i = 0; i < total_bits; i++) {
        // If current bit is 1, result = (result * base_temp) % M
        if(LN_get_bit(exp, i) == 1) {
            LN mult_res;
            LN_LN_mult(&result, &base_temp, &mult_res);
            LN_barrett_redu(&mult_res, ctx, &result);
        }
        
        // base_temp = (base_temp * base_temp) % M
        LN sqr_res;
        LN_LN_mult(&base_temp, &base_temp, &sqr_res);
        LN_barrett_redu(&sqr_res, ctx, &base_temp);
    }
    
    // Transfer memory ownership to output
    *out = result;
    return 1;
}

__global__ void batch_rsa_kernel(LN *messages, LN *exponents, LN_BarrettSet *ctx, LN *ciphertexts, int total_threads) {

    // thread index
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= total_threads) return;

    LN out_container;
    out_container.size = 1;
    for(int i=0; i<128; i++) out_container.nums[i] = 0;

    // Threads does independent messages concurrently 
    LN_mod_exp(&messages[i], &exponents[i], &ctx[i], &out_container);

    ciphertexts[i] = out_container;
}

// Standard Division (Shift_Subtract)
int CPU_LN_div_mod(const LN *numer, const LN *denom, LN *quotient, LN *remainder) {
    // Div by zero case
    if(denom->size == 1 && denom->nums[0] == 0) {
        return 0; 
    }

    // Initialize quotient and remainder to 0
    quotient->size = numer->size;
    for(int i=0; i<128; i++) quotient->nums[i] = 0;
    remainder->size = 1;
    for(int i=0; i<128; i++) remainder->nums[i] = 0;
    if(!quotient->nums || !remainder->nums){
        return 0;
    }

    uint64_t total_bits = LN_bit_length(numer);

    // Process from MSB down to LSB
    for (int64_t i = total_bits - 1; i >= 0; i--) {
        // remainder = remainder << 1
        LN temp_rem;
        LN_L_shift(remainder, 1, &temp_rem);
        *remainder = temp_rem;

        // remainder[0] = numer[i]
        remainder->nums[0] |= LN_get_bit(numer, i);

        // if remainder >= denom
        if(LN_cmp(remainder, denom) >= 0) {
            // remainder = remainder - denom
            LN new_rem;
            LN_sub(remainder, denom, &new_rem);
            *remainder = new_rem;
            
            // quotient[i] = 1
            LN_set_bit(quotient, i);
        }
    }

    // Normalize quotient
    while(quotient->size > 1 && quotient->nums[quotient->size - 1] == 0){
        quotient->size--;
    } 
    
    return 1;
}



// Random 64 bit Num
uint64_t rand_64() {
    uint64_t r = 0;
    for (int i = 0; i < 4; i++) {
        r = (r << 16) | (rand() & 0xFFFF);
    }
    return r;
}

// Generate random N bit Large num
void LN_rand_num(LN *num, uint64_t bits) {

    uint64_t limbs = (bits + 63) / 64;
    num->size = limbs;
    
    for (uint64_t i = 0; i < limbs; i++) {
        num->nums[i] = rand_64();
    }
    
    // Mask the most significant limb
    uint64_t extra_bits = bits % 64;
    if(extra_bits > 0) {
        uint64_t mask = (1ULL << extra_bits) - 1;
        num->nums[limbs - 1] &= mask;
    }
    // Ensure the highest bit is 1
    num->nums[limbs - 1] |= (1ULL << ((extra_bits == 0 ? 64 : extra_bits) - 1));
}

// Barret Setup, mu = floor(2^(2k) / M)
int LN_setup_barrett(const LN *M, LN_BarrettSet *ctx) {

    ctx->k = LN_bit_length(M);
    
    // Copy M into setup context
    ctx->M = *M;
    for(int i=0; i<128; i++) ctx->mu.nums[i] = 0;

    // Compute 2^(2k)
    LN b_2k;
    for(int i=0; i<128; i++) {
        b_2k.nums[i] = 0;
    }
    uint64_t target_bit = 2 * ctx->k;
    b_2k.size = (target_bit / 64) + 1;
    b_2k.nums[target_bit / 64] |= (1ULL << (target_bit % 64));

    // Calculate mu = 2^(2k) / M
    LN discard_rem = {0};
    CPU_LN_div_mod(&b_2k, &(ctx->M), &(ctx->mu), &discard_rem);

    return 1;

}

// Convert LN to OpenSSL BIGNUM
void LN_to_BN(LN *ln, BIGNUM **bn) {
    uint64_t bytes = ln->size * 8;
    unsigned char *buf = (unsigned char *)malloc(bytes);
    
    // Convert to Big-Endian byte array for OpenSSL consumption
    for (uint64_t i = 0; i < ln->size; i++) {
        uint64_t limb = ln->nums[i];
        for (int j = 0; j < 8; j++) {
            buf[bytes - 1 - (i * 8 + j)] = (limb >> (j * 8)) & 0xFF;
        }
    }
    
    *bn = BN_bin2bn(buf, bytes, NULL);
    free(buf);
}


// Modified veresion of rsa check
int main(void) {
    // same as cpu testing
    int iters = 10000; 
    bool seeded = true;
    int seed = 1020;

    printf("GPU testing started...\n\n");
    if (seeded) {
        srand(seed);
        printf("Running %d parallel tasks with Seed %d\n\n", iters, seed);
    } else {
        srand(time(NULL));
        printf("Running %d parallel tasks with Random Seed\n\n", iters);
    }

    // Allocate memory on CPU
    LN *h_messages = (LN*)malloc(iters * sizeof(LN));
    LN *h_exponents = (LN*)malloc(iters * sizeof(LN));
    LN *h_ciphertexts = (LN*)malloc(iters * sizeof(LN));
    LN_BarrettSet *h_ctx = (LN_BarrettSet*)malloc(iters * sizeof(LN_BarrettSet));


    // Generate the random testing data
    // creates the first random 2048-but message at index 0 
    LN N, e;
    printf("Generating Random RSA Parameters on Host CPU...\n");
    LN_rand_num(&N, 2048); // Generate 2048-bit modulus
    LN_rand_num(&h_messages[0], 2048); // Generate initial base message
    
    // Fill the rest of the 10000 array
    for (int i = 1; i < iters; i++) {
        LN_rand_num(&h_messages[i], 2048);
    }
    
    // Standard RSA public exponent 65537, 0x10001
    e.size = 1;
    e.nums[0] = 65537;
    for(int i = 1; i < 128; i++) e.nums[i] = 0;

    
    // Precompute Barrett Context for N one time on CPU
    LN_setup_barrett(&N, &h_ctx[0]);
    
    // Broadcast the common key parameters across all threads
    for (int i = 0; i < iters; i++) {
        h_exponents[i] = e;
        h_ctx[i] = h_ctx[0];
    }

    printf("\nReserving memory on the GPU...\n");
    LN *device_messages, *device_exponents, *device_ciphertexts;
    LN_BarrettSet *device_ctx;
    
    cudaMalloc((void**)&device_messages, iters * sizeof(LN));
    cudaMalloc((void**)&device_exponents, iters * sizeof(LN));
    cudaMalloc((void**)&device_ciphertexts, iters * sizeof(LN));
    cudaMalloc((void**)&device_ctx, iters * sizeof(LN_BarrettSet));

    printf("COpying data from CPU to GPU...\n");
    cudaMemcpy(device_messages, h_messages, iters * sizeof(LN), cudaMemcpyHostToDevice);
    cudaMemcpy(device_exponents, h_exponents, iters * sizeof(LN), cudaMemcpyHostToDevice);
    cudaMemcpy(device_ctx, h_ctx, iters * sizeof(LN_BarrettSet), cudaMemcpyHostToDevice);

    // GPU Config
    int threadsPerBlock = 128;
    int blocksPerGrid = (iters+threadsPerBlock - 1) / threadsPerBlock;

    printf("Running RSA Encryption %d times in parallel...\n", iters);
    clock_t start_time = clock();
    
    batch_rsa_kernel<<<blocksPerGrid, threadsPerBlock>>>(device_messages, device_exponents, device_ctx, device_ciphertexts, iters);
    
    // This is important to prevent error
    cudaDeviceSynchronize();
    
    clock_t end_time = clock();
    double gpu_time = (double)(end_time - start_time) / CLOCKS_PER_SEC;
    printf("GPU Processing Time: %f seconds\n", gpu_time);


    // OPENSSL bignum test copied from cpu code
    printf("\nRunning OpenSSL RSA Encryption %d times sequentially on CPU for Validation...\n", iters);
    
    BIGNUM *bn_N = NULL, *bn_m = NULL, *bn_e = NULL, *bn_ciphertext = BN_new();
    BN_CTX *bn_ctx = BN_CTX_new();

    // Turn LN values to BIGNUMs
    LN_to_BN(&N, &bn_N);
    LN_to_BN(&e, &bn_e);

    clock_t start_ssl = clock();
    // Run validation loop to capture verification profile times
    for (int i = 0; i < iters; i++) {
        if (bn_m) BN_free(bn_m);
        LN_to_BN(&h_messages[i], &bn_m);
        BN_mod_exp(bn_ciphertext, bn_m, bn_e, bn_N, bn_ctx);
    }
    clock_t end_ssl = clock();
    double ssl_time = (double)(end_ssl - start_ssl) / CLOCKS_PER_SEC;
    printf("    OpenSSL Time:   %f seconds\n", ssl_time);


    // PERFORMANCE METRICS RUN ANALYSIS
    printf("\n--- Performance---\n");
    printf("GPU Barrett: %f seconds\n", gpu_time);
    printf("OpenSSL (CPU only): %f seconds\n", ssl_time);
    
    if (gpu_time > 0) {
        printf("GPU parallel layout is %.2fx faster than serial OpenSSL execution\n", ssl_time / gpu_time);
    }


    printf("\n--- Correctness Check ---\n");
    // Sends data back from GPU -> CPU
    cudaMemcpy(h_ciphertexts, device_ciphertexts, iters * sizeof(LN), cudaMemcpyDeviceToHost);

    // Convert our LN result to a BIGNUM and compare it to OpenSSL's result
    BIGNUM *bn_ln_result = NULL;
    LN_to_BN(&h_ciphertexts[0], &bn_ln_result);

    if (bn_m) {
        BN_free(bn_m);
    }
    LN_to_BN(&h_messages[0], &bn_m);
    BN_mod_exp(bn_ciphertext, bn_m, bn_e, bn_N, bn_ctx);

    if (BN_cmp(bn_ciphertext, bn_ln_result) == 0) {
        printf("SUCCESS! GPU implementation matches OpenSSL results.\n\n");
    } else {
        printf("FAILED! Mismatch discovered .\n\n");
    }

    // Cleanup mems
    cudaFree(device_messages); 
    cudaFree(device_exponents); 
    cudaFree(device_ciphertexts); 
    cudaFree(device_ctx);
    free(h_messages); 
    free(h_exponents); 
    free(h_ciphertexts); 
    free(h_ctx);
    BN_free(bn_N); 
    BN_free(bn_m); 
    BN_free(bn_e); 
    BN_free(bn_ciphertext); 
    BN_free(bn_ln_result);
    BN_CTX_free(bn_ctx);

    return 0;
}
