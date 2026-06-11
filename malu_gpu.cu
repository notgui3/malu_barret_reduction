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
    uint64_t nums[8192]; // 8192 make sure no overflow
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

__device__ int LN_R_shift(LN *in, uint32_t shift_amount, LN *out){

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

__device__ int LN_L_shift(LN *in, uint32_t shift_amount, LN *out){

    if(!in || !out){
      return 0;
    } 
    
    uint32_t limb_shift = shift_amount / 64;
    uint32_t bit_shift = shift_amount % 64;

    // Max possible new size: current size + full limb shifts + 1 for overflow bits
    out->size = in->size + limb_shift + (bit_shift > 0 ? 1 : 0);

    if(out->size > 8192){
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
__device__ int LN_int_mult(LN *op1, uint64_t op2, LN *out) {

    if(!op1 || !out) {
        return 0;
    }
    
    out->size = op1->size + 1; // Max possible size
    if (out->size > 8192) {
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
__device__ int LN_LN_mult(LN *op1, LN *op2, LN *out) {

    if(!op1 || !op2 || !out){
        return 0;
    }

    out->size = op1->size + op2->size;
    if (out->size > 8192) {
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
__device__ int LN_cmp(const LN *op1, const LN *op2) {
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
__device__ int LN_sub(const LN *op1, const LN *op2, LN *out) {
    if(LN_cmp(op1, op2) < 0){
        return 0;
    }

    out->size = op1->size;

    if (out->size > 8192) {
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
__device__ uint64_t LN_bit_length(const LN *num) {

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
__device__ int LN_get_bit(const LN *num, uint64_t bit_index) {
    uint64_t limb = bit_index / 64;

    if(limb >= num->size){
        return 0;
    }

    return (num->nums[limb] >> (bit_index % 64)) & 1;
}

// Helper to set a specific bit in a limb to 1
__device__ void LN_set_bit(LN *num, uint64_t bit_index) {
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
    if (quotient->size > 8192) {
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
    for (uint64_t i = 1; i < 8192; i++) {
        result.nums[i] = 0;
    }

    // base_temp = base mod M
    LN base_temp;
    base_temp.size = 1;
    base_temp.nums[0] = 0;
    for (uint64_t k = 1; k < 8192; k++) {
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




