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



// Most functions use a pointer for output, returns 1 if function succeeded, 0 if not

typedef struct{
    uint64_t *nums;
    uint64_t size;
} LN;


void free_LN(LN *num) {

    if(num != NULL) {
        free(num->nums);
        num->nums = NULL;
        num->size = 0;
    }

}

void print_64(uint64_t num_64){

    char buffer[21];
    snprintf(buffer, sizeof(buffer), "%" PRIu64, num_64);
    printf("int64: %s \n", buffer);

}

void print_64_hex(uint64_t num_64){

    char buffer[21];
    snprintf(buffer, sizeof(buffer), "%" PRIx64, num_64);
    printf("int64: %s \n", buffer);

}

void print_LN_hex(LN large_num){

    for(int i = large_num.size; i > 0; i--){
        printf("%i ", i);
        print_64_hex(*(large_num.nums+(i-1)));
    }

}

void print_LN(LN large_num){

    for(int i = large_num.size; i > 0; i--){
        printf("%i ", i);
        print_64(*(large_num.nums+(i-1)));
    }

}

static int hex_char_to_val(char c) {

    if(c >= '0' && c <= '9'){
        return c - '0';
    }

    if(c >= 'a' && c <= 'f'){
        return 10 + (c - 'a');
    }

    if(c >= 'A' && c <= 'F') 
    {return 10 + (c - 'A');
    }
    return -1;
}

int hex_to_large_num(LN *large_num, const char *str) {
    if(large_num == NULL || str == NULL) return 0;

    // Parse out hex prefix
    if(str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
        str += 2;
    }

    //Skip leading zeros
    while(*str == '0') {
        str++;
    }

    uint64_t len = strlen(str);
    
    //Initialize as 0 if length was 0
    if(len == 0) {
        large_num->nums = (uint64_t *)calloc(1, sizeof(uint64_t));
        if(large_num->nums == NULL) return 0;
        large_num->size = 1;
        return 1;
    }

    // Find number of uint64_t needed
    uint64_t calculated_size = (len + 15) / 16;

    // Allocate mem
    large_num->nums = (uint64_t *)calloc(calculated_size, sizeof(uint64_t));
    if(large_num->nums == NULL){
        return 0;
    } 
    large_num->size = calculated_size;

    uint64_t current_limb = 0;
    int shift_amount = 0;
    uint64_t accumulated_value = 0;

    // Process from right to left, little endian, LSB at index 0
    for (uint64_t i = len; i > 0; i--) {
        char c = str[i - 1];
        int val = hex_char_to_val(c);
        
        if(val < 0) {
            free(large_num->nums);
            large_num->nums = NULL;
            large_num->size = 0;
            return 0;
        }

        accumulated_value |= ((uint64_t)val << shift_amount);
        shift_amount += 4;

        if(shift_amount == 64 || i == 1) {
            large_num->nums[current_limb] = accumulated_value;
            current_limb++;
            accumulated_value = 0;
            shift_amount = 0;
        }
    }

    return 1;
}

int LN_R_shift(LN *in, uint32_t shift_amount, LN *out){

    if(!in || !out) {
        return 0;
    }
    
    uint32_t limb_shift = shift_amount / 64;
    uint32_t bit_shift = shift_amount % 64;

    // If we shift right by more limbs than we have, the result is 0
    if(limb_shift >= in->size) {
        out->size = 1;
        out->nums = (uint64_t *)calloc(1, sizeof(uint64_t));
        return 1;
    }

    out->size = in->size - limb_shift;
    out->nums = (uint64_t *)calloc(out->size, sizeof(uint64_t));
    if(!out->nums) return 0;

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

int LN_L_shift(LN *in, uint32_t shift_amount, LN *out){

    if(!in || !out){
      return 0;
    } 
    
    uint32_t limb_shift = shift_amount / 64;
    uint32_t bit_shift = shift_amount % 64;

    // Max possible new size: current size + full limb shifts + 1 for overflow bits
    out->size = in->size + limb_shift + (bit_shift > 0 ? 1 : 0);
    out->nums = (uint64_t *)calloc(out->size, sizeof(uint64_t));

    if(!out->nums){
      return 0;
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

// Add two LNs, out = op1 + op2
int LN_add(const LN *op1, const LN *op2, LN *out){
    
    if(!op1 || !op2 || !out){
        return 0;
    }

    // Maximum bit size is the larger size + 1 
    uint64_t max_size = (op1->size > op2->size) ? op1->size : op2->size;
    out->size = max_size + 1;

    out->nums = (uint64_t *)calloc(out->size, sizeof(uint64_t));
    if(!out->nums){
        return 0;
    }

    uint64_t carry = 0;
    
    for(uint64_t i = 0; i < max_size; i++){
        uint64_t a = (i < op1->size) ? op1->nums[i] : 0;
        uint64_t b = (i < op2->size) ? op2->nums[i] : 0;

        uint64_t sum = a + b + carry;

        // Determine if an overflow occurred in this limb step to set the next carry
        if(sum < a || (sum == a && carry > 0)){
            carry = 1;
        } 
        else{
            carry = 0;
        }

        out->nums[i] = sum;
    }

    out->nums[max_size] = carry;

    // Remove leading zero limbs
    while(out->size > 1 && out->nums[out->size - 1] == 0){
        out->size--;
    }

    return 1;
}

// LN * LN
int LN_LN_mult(LN *op1, LN *op2, LN *out) {

    if(!op1 || !op2 || !out){
        return 0;
    }

    out->size = op1->size + op2->size;
    out->nums = (uint64_t *)calloc(out->size, sizeof(uint64_t));
    if(!out->nums){
        return 0;
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
int LN_cmp(const LN *op1, const LN *op2) {
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
int LN_sub(const LN *op1, const LN *op2, LN *out) {
    if(LN_cmp(op1, op2) < 0){
        return 0;
    }

    out->size = op1->size;
    out->nums = (uint64_t *)calloc(out->size, sizeof(uint64_t));

    if(!out->nums){
        return 0;
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
uint64_t LN_bit_length(const LN *num) {

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
int LN_get_bit(const LN *num, uint64_t bit_index) {
    uint64_t limb = bit_index / 64;

    if(limb >= num->size){
        return 0;
    }

    return (num->nums[limb] >> (bit_index % 64)) & 1;
}

// Helper to set a specific bit in a limb to 1
void LN_set_bit(LN *num, uint64_t bit_index) {
    uint64_t limb = bit_index / 64;

    if(limb < num->size) {
        num->nums[limb] |= (1ULL << (bit_index % 64));
    }
}

// Standard Division (Shift_Subtract)
int LN_div_mod(const LN *numer, const LN *denom, LN *quotient, LN *remainder) {
    // Div by zero case
    if(denom->size == 1 && denom->nums[0] == 0) {
        return 0; 
    }
    

    // Initialize quotient and remainder to 0
    quotient->size = numer->size;
    quotient->nums = (uint64_t *)calloc(quotient->size, sizeof(uint64_t));
    
    remainder->size = 1;
    remainder->nums = (uint64_t *)calloc(1, sizeof(uint64_t));

    if(!quotient->nums || !remainder->nums){
        return 0;
    }

    uint64_t total_bits = LN_bit_length(numer);

    // Process from MSB down to LSB
    for (int64_t i = total_bits - 1; i >= 0; i--) {
        // remainder = remainder << 1
        LN temp_rem;
        LN_L_shift(remainder, 1, &temp_rem);
        free_LN(remainder);
        *remainder = temp_rem;

        // remainder[0] = numer[i]
        remainder->nums[0] |= LN_get_bit(numer, i);

        // if remainder >= denom
        if(LN_cmp(remainder, denom) >= 0) {
            // remainder = remainder - denom
            LN new_rem;
            LN_sub(remainder, denom, &new_rem);
            free_LN(remainder);
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
int LN_barrett_redu(LN *X, const LN_BarrettSet *ctx, LN *out) {
    if(!X || !ctx || !out){
        return 0;
    }

    LN q1 = {0}, q2 = {0}, q3 = {0};
    LN q3_M = {0}, R = {0};

    // q1 = X >> (k - 1)
    if(ctx->k > 1) {
        LN_R_shift(X, ctx->k - 1, &q1);
    } else {
        q1.size = X->size;
        q1.nums = (uint64_t*)calloc(q1.size, sizeof(uint64_t));
        memcpy(q1.nums, X->nums, q1.size * sizeof(uint64_t));
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
        R.nums = (uint64_t*)calloc(R.size, sizeof(uint64_t));
        memcpy(R.nums, X->nums, R.size * sizeof(uint64_t));
    }

    // Corrections: while R >= M, R = R - M
    while(LN_cmp(&R, &(ctx->M)) >= 0) {
        LN temp_R;
        LN_sub(&R, &(ctx->M), &temp_R);
        free_LN(&R);
        R = temp_R;
    }

    // Transfer memory and values to output
    out->size = R.size;
    out->nums = R.nums;

    // Freeing Temp Vars
    free_LN(&q1);
    free_LN(&q2);
    free_LN(&q3);
    free_LN(&q3_M);

    return 1;
}

// Modular Multiplication, out = (op1 * op2) mod M
int LN_mod_mult(LN *op1, LN *op2, const LN_BarrettSet *ctx, LN *out){
    
    if(!op1 || !op2 || !ctx || !out){
        return 0;
    }

    LN intermediate_product = {0};

    // Multiply
    if(!LN_LN_mult(op1, op2, &intermediate_product)){
        return 0;
    }
    
    free_LN(out);

    // Barrett Reduction Mod
    if(!LN_barrett_redu(&intermediate_product, ctx, out)){
        free_LN(&intermediate_product);
        return 0;
    }

    free_LN(&intermediate_product);

    return 1;
}

// Mod Expoenetation, Square Multiply, out = (base ^ exp) mod M
int LN_mod_exp(LN *base, LN *exp, LN_BarrettSet *ctx, LN *out) {

    if(!base || !exp || !ctx || !out){
        return 0;
    }

    // Set base result to 1
    LN result = {0};
    result.size = 1;
    result.nums = (uint64_t*)calloc(1, sizeof(uint64_t));
    result.nums[0] = 1;

    // base_temp = base mod M
    LN base_temp = {0};
    LN_barrett_redu(base, ctx, &base_temp); 

    uint64_t total_bits = LN_bit_length(exp);

    // Process from LSB to MSB
    for (uint64_t i = 0; i < total_bits; i++) {
        // If current bit is 1, result = (result * base_temp) % M
        if(LN_get_bit(exp, i) == 1) {
            LN mult_res = {0};
            LN_LN_mult(&result, &base_temp, &mult_res);
            free_LN(&result);
            LN_barrett_redu(&mult_res, ctx, &result);
            free_LN(&mult_res);
        }
        
        // base_temp = (base_temp * base_temp) % M
        LN sqr_res = {0};
        LN_LN_mult(&base_temp, &base_temp, &sqr_res);
        free_LN(&base_temp);
        LN_barrett_redu(&sqr_res, ctx, &base_temp);
        free_LN(&sqr_res);
    }

    free_LN(&base_temp);
    
    // Transfer memory ownership to output
    out->size = result.size;
    out->nums = result.nums;
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
    num->nums = (uint64_t *)calloc(limbs, sizeof(uint64_t));
    
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
    ctx->M.size = M->size;
    ctx->M.nums = (uint64_t *)calloc(M->size, sizeof(uint64_t));
    memcpy(ctx->M.nums, M->nums, M->size * sizeof(uint64_t));

    // Compute 2^(2k)
    LN b_2k = {0};
    uint64_t target_bit = 2 * ctx->k;
    b_2k.size = (target_bit / 64) + 1;
    b_2k.nums = (uint64_t *)calloc(b_2k.size, sizeof(uint64_t));
    b_2k.nums[target_bit / 64] |= (1ULL << (target_bit % 64));

    // Calculate mu = 2^(2k) / M
    LN discard_rem = {0};
    LN_div_mod(&b_2k, &(ctx->M), &(ctx->mu), &discard_rem);

    free_LN(&b_2k);
    free_LN(&discard_rem);
    return 1;

}


void free_barrett_ctx(LN_BarrettSet *ctx) {
    free_LN(&(ctx->M));
    free_LN(&(ctx->mu));
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


int barret_vs_standard(int iters, uint64_t x_bit_size, uint64_t m_bit_size, bool seeded, int seed){

    printf("Barrett vs Standard Division Benchmark\n\n");
    printf("X value bits: %i, M value bits: %i\n\n", x_bit_size, m_bit_size);

    if(seeded){
        srand(seed);
        printf("Running %i times with Seed %i\n\n", iters, seed);
    }
    else{
        srand(time(NULL));
        printf("Running %i times with Random Seed\n\n", iters);
    }
    


    LN M = {0};
    LN X = {0};
    LN barrett_res = {0};
    LN div_quotient = {0};
    LN div_remainder = {0};
    LN_BarrettSet ctx = {0};


    printf("Generating Random Value X and Modulus M\n");
    LN_rand_num(&X, x_bit_size);
    LN_rand_num(&M, m_bit_size);

    // STANDARD SHIFT SUBTRACT DIVISION
    printf("\nRunning Standard Division %d times\n", iters);
    clock_t stand_start = clock();
    
    for (int i = 0; i < iters; i++) {
        // Free previous iters' memory
        free_LN(&div_quotient);
        free_LN(&div_remainder);
        
        LN_div_mod(&X, &M, &div_quotient, &div_remainder);
    }
    
    clock_t stand_end = clock();
    double stand_time = (double)(stand_end - stand_start) / CLOCKS_PER_SEC;
    printf("    Standard Div Time (Total): %f seconds\n", stand_time);

    // BARRETT REDUCTION
    printf("\nRunning Barrett Reduction...\n");
    
    // Time the setup (done ONCE)
    clock_t setup_start = clock();
    LN_setup_barrett(&M, &ctx);
    clock_t setup_end = clock();
    double setup_time = (double)(setup_end - setup_start) / CLOCKS_PER_SEC;
    printf("    Barrett Precompute (mu) Time: %f seconds\n", setup_time);

    // Time the reduction iters
    clock_t bar_start = clock();
    
    for (int i = 0; i < iters; i++) {
        free_LN(&barrett_res);
        LN_barrett_redu(&X, &ctx, &barrett_res);
    }
    
    clock_t bar_end = clock();
    double barrett_time = (double)(bar_end - bar_start) / CLOCKS_PER_SEC;
    printf("    Barrett Loop Time (Total):    %f seconds\n", barrett_time);


    // VERIFICATION
    printf("\n--- Comparison ---\n");
    printf("Standard Total Time: %f seconds\n", stand_time);
    printf("Barrett Total Time:  %f seconds (Setup %fs + Loop %fs)\n", 
           setup_time + barrett_time, setup_time, barrett_time);
           
    if(barrett_time > 0) {
        printf("\n-> Loop Speedup: Barrett is %.2fx faster than Standard Division per reduction.\n", 
               stand_time / barrett_time);
    }

    printf("\n--- Correctness ---\n");
    if(LN_cmp(&div_remainder, &barrett_res) == 0) {
        printf("SUCCESS (Barrett = Standard Modulo)\n");
    } else {
        printf("FAILED\n");
        printf("Standard result bits: %llu\n", LN_bit_length(&div_remainder));
        printf("Barrett result bits:  %llu\n", LN_bit_length(&barrett_res));
    }

    FILE *fptr;
    fptr = fopen("stats/speedup_9800x3d.txt", "a");
    if (fptr == NULL) {
        printf("Error opening the file!\n");
        return 1; 
    }
    // Write number of iterations, and speedup
    fprintf(fptr, "%i, %f\n", iters, stand_time/barrett_time);
    fclose(fptr);

    // Cleanup Memory
    free_LN(&M);
    free_LN(&X);
    free_LN(&barrett_res);
    free_LN(&div_quotient);
    free_LN(&div_remainder);
    free_barrett_ctx(&ctx);
}


int rsa_check(int iters, bool seeded, int seed) {

    printf("LN vs OpenSSL RSA Verification\n\n");
    if(seeded){
        srand(seed);
        printf("Running %i times with Seed %i\n\n", iters, seed);
    }
    else{
        srand(time(NULL));
        printf("Running %i times with Random Seed\n\n", iters);
    }


    LN N = {0}; // RSA Key Modulus
    LN m = {0}; // Message
    LN e = {0}; // Public Exponent
    LN ln_ciphertext = {0};
    LN_BarrettSet ctx = {0};

    // 1. Setup simulated RSA parameters
    printf("Generating Random RSA Parameters\n");
    LN_rand_num(&N, 2048); 
    LN_rand_num(&m, 2048);
    
    // Standard RSA public exponent 65537, 0x10001
    e.size = 1;
    e.nums = (uint64_t*)calloc(1, sizeof(uint64_t));
    e.nums[0] = 65537;

    // Precompute Barrett Context for N
    printf("Precomputing Barrett Context for Modulus N\n");
    clock_t setup_start = clock();
    LN_setup_barrett(&N, &ctx);
    clock_t setup_end = clock();
    printf("    Setup Time: %f seconds\n", (double)(setup_end - setup_start) / CLOCKS_PER_SEC);

    // LN TEST
    printf("\nRunning LN RSA Encryption %d times\n", iters);
    clock_t start_ln = clock();
    
    for (int i = 0; i < iters; i++) {
        free_LN(&ln_ciphertext);
        LN_mod_exp(&m, &e, &ctx, &ln_ciphertext);
    }
    
    clock_t end_ln = clock();
    double ln_time = (double)(end_ln - start_ln) / CLOCKS_PER_SEC;
    printf("    LN Time: %f seconds\n", ln_time);


    // OPENSSL BIGNUM TEST
    printf("\nRunning OpenSSL RSA Encryption %d times...\n", iters);
    
    BIGNUM *bn_N = NULL, *bn_m = NULL, *bn_e = NULL, *bn_ciphertext = BN_new();
    BN_CTX *bn_ctx = BN_CTX_new();

    // Turn LN values to BIGNUMs
    LN_to_BN(&N, &bn_N);
    LN_to_BN(&m, &bn_m);
    LN_to_BN(&e, &bn_e);

    clock_t start_ssl = clock();
    
    for (int i = 0; i < iters; i++) {
        BN_mod_exp(bn_ciphertext, bn_m, bn_e, bn_N, bn_ctx);
    }
    
    clock_t end_ssl = clock();
    double ssl_time = (double)(end_ssl - start_ssl) / CLOCKS_PER_SEC;
    printf("    OpenSSL Time:   %f seconds\n", ssl_time);


    // VERIFICATION
    printf("\n--- Performance ---\n");
    printf("LN (Barrett): %f seconds\n", ln_time);
    printf("OpenSSL: %f seconds\n", ssl_time);
    
    if(ssl_time > 0) {
        printf("OpenSSL is %.2fx faster than LN RSA.\n", ln_time / ssl_time);
    }
    FILE *fptr;
    fptr = fopen("stats/RSA_9800x3d.txt", "a");
    if (fptr == NULL) {
        printf("Error opening the file!\n");
        return 1; 
    }
    // Write number of iterations, and speedup
    fprintf(fptr, "%i, %f\n", iters, ln_time / ssl_time);
    fclose(fptr);

    printf("\n--- Correctness Check ---\n");
    // Convert our LN result to a BIGNUM and compare it to OpenSSL's result
    BIGNUM *bn_ln_result = NULL;
    LN_to_BN(&ln_ciphertext, &bn_ln_result);

    if(BN_cmp(bn_ciphertext, bn_ln_result) == 0) {
        printf("SUCCESS, LN RSA matches OpenSSL\n");
    } else {
        printf("FAILED\n");
    }

    // Cleanup mems
    free_LN(&N);
    free_LN(&m);
    free_LN(&e);
    free_LN(&ln_ciphertext);
    free_barrett_ctx(&ctx);
    BN_free(bn_N);
    BN_free(bn_m);
    BN_free(bn_e);
    BN_free(bn_ciphertext);
    BN_free(bn_ln_result);
    BN_CTX_free(bn_ctx);

    return 0;
}

int main(void) {
    
    printf("BARRET VS STANDARD COMPARISON\n");
    printf("----------------------------\n");
    int iters[5] = {1, 10, 100, 1000, 10000};
    // Iterations, X bit size, M bit size, Seeded?, Seed
    for(size_t t = 0; t < sizeof(iters); t++){
        for(int i = 0; i < 1000; i++){
            barret_vs_standard(iters[t], 4096, 2048, 0, 100);
        }
    }
        

    printf("\n\n\n\n\n\n");

    printf("RSA OPENSSL COMPARISON\n");
    printf("----------------------------\n");
    // Iterations, Seeded?, Seed
    for(size_t t = 0; t < 1000; t++){
        rsa_check(1000, 0, 1020);
    }
    return 0;
}

