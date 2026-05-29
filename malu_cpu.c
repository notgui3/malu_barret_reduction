#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>


typedef struct{
    uint64_t *nums;
    uint64_t size;
} LN;


void free_LN(LN *num) {
    if (num != NULL) {
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
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

int hex_to_large_num(LN *large_num, const char *str) {
    if (large_num == NULL || str == NULL) return 0;

    //Skip hex prefix
    if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
        str += 2;
    }

    //Skip leading zeros
    while (*str == '0') {
        str++;
    }

    uint64_t len = strlen(str);
    
    //Initialize as 0 if length was 0
    if (len == 0) {
        large_num->nums = (uint64_t *)calloc(1, sizeof(uint64_t));
        if (large_num->nums == NULL) return 0;
        large_num->size = 1;
        return 1;
    }

    // Compute exact number of uint64_t needed
    uint64_t calculated_size = (len + 15) / 16;

    // Allocate memory
    large_num->nums = (uint64_t *)calloc(calculated_size, sizeof(uint64_t));
    if (large_num->nums == NULL) return 0;
    large_num->size = calculated_size;

    uint64_t current_limb = 0;
    int shift_amount = 0;
    uint64_t accumulated_value = 0;

    // Process from right to left, little endian, LSB at index 0
    for (uint64_t i = len; i > 0; i--) {
        char c = str[i - 1];
        int val = hex_char_to_val(c);
        
        if (val < 0) {
            free(large_num->nums);
            large_num->nums = NULL;
            large_num->size = 0;
            return 0;
        }

        accumulated_value |= ((uint64_t)val << shift_amount);
        shift_amount += 4;

        if (shift_amount == 64 || i == 1) {
            large_num->nums[current_limb] = accumulated_value;
            current_limb++;
            accumulated_value = 0;
            shift_amount = 0;
        }
    }

    return 1;
}

// int LN_R_shift(LN *in, int shift_amount, LN *out){

// }

int LN_L_shift(LN *in, int shift_amount, LN *out){
    out->nums = (uint64_t *)calloc(out->size, sizeof(uint64_t));

    for(int i = in->size; i > 1; i--){
        out->nums[i-1] = ( in->nums[i-1] << shift_amount) | ( in->nums[i-2] >> (64 - shift_amount) );
    }
    out->nums[0] = ( in->nums[0] << shift_amount);
    print_64( (in->nums[0] << 10) >> 10);

    return 1;
}

// int LN_LN_mult(LN *op1, LN *op2, LN *out){

// }

// int LN_int_mult(LN *op1, uint64_t op2, LN *out){

// }

// int LN_LN_div(LN *numer, LN* denom, LN *out){

// }

// int LN_int_div(LN *numer, uint64_t denom, LN *out){

// }


int main(void){
    char *number =  "0FFFFFFFFFFFFFFF"
                    "1FFFFFFFFFFFFFFF"
                    "2FFFFFFAFFFFFFFF"
                    "3FFFFFFFFFFFFFFF"
                    "4FFFFFFF1FFFFFFF"
                    "5FFF2FFFFFFFFFFF"
                    "6FFFFFFFFFAFFFFF"
                    "7FFFFFFFFFFFFFFF"
                    "8FFFFFFFFFFFFFFF"
                    "9FFFFFFFFAFFFFFF"
                    "AFFF3FFFFFFFFFFF"
                    "0123456789ABCDEF";
    LN large_num;
    if (hex_to_large_num(&large_num, number)){
        printf("success \n");
    }

    print_LN_hex(large_num);

    LN LN_shifted;
    LN_shifted.size = large_num.size;

    LN_L_shift(&large_num, 64, &LN_shifted);

    print_LN_hex(LN_shifted);



}




long bar_redu(long a, long n){
    long k = 0;
    long b_k = 2;

    int done = 0;

    while (!done) {
        if( (b_k < a) | (b_k > LONG_MAX/2)){
            done = 1;
        }
        b_k = b_k << 1;
        k += 1;
    }

    b_k = 2 << (2*k);

    long m = (b_k)/n;
    long q = (a*m) >> (2*k);

    long r = a - q * n;

    while (r >= n)
        r -= n;

    while (r < 0)
        r += n;

    return r;

}

long mod(long a, long n){
    long quot = a/n;
    return a - quot*n;
}

long mod_mul(long a, long b, long n){
    long mult = a * b;
    //Barret Reduction Target
    // return mod(mult, n);
    return bar_redu(mult, n);

}

long mod_exp(long base, long ko, long n) {
    long b = bar_redu(base, n);
    long b_k = 1;

    long e = ko;

    while (e > 0){

        if(mod(e, 2) == 1){
            b_k = mod_mul(b_k, b, n);
        }

        b = mod_mul(b, b, n);

        e = e/2;
    }

    return b_k;
}




// long main(void){

//     long test = mod_mul(20, 10, 7);
//     printf("%li \n", test);

//     int errors = 0;
//     long error_margin = 0;
//     int largest_error = 0;

//     struct timespec start_base, end_base; 
//     struct timespec start, end;
    
//     double time_spent_base = 0;
//     double time_spent = 0;
//     int iters = 200;

//     for(long i = 1; i < iters; i++){
//         for(long j = 1; j < iters; j++){
//             // printf("Loop %li, %li", i, j);
//             long a = LONG_MAX - i;
//             long n = LONG_MAX - j;

//             timespec_get(&start_base, TIME_UTC);
//             long base = a%n;
//             timespec_get(&end_base, TIME_UTC);
            
//             time_spent_base += (end_base.tv_sec - start_base.tv_sec) + 
//                         (end_base.tv_nsec - start_base.tv_nsec) / 1000000000.0;

//             timespec_get(&start, TIME_UTC);
//             long bar = bar_redu(a,n);
//             timespec_get(&end, TIME_UTC);
//             time_spent += (end.tv_sec - start.tv_sec) + 
//                         (end.tv_nsec - start.tv_nsec) / 1000000000.0;
            
//             long diff = abs( (int) (base - bar) );
//             // printf("%li \n", diff);
//             if( diff != 0 ){
//                 errors++;
//                 error_margin += diff;
//             }
//             if(diff > largest_error){
//                 largest_error = diff;
//             }
//         }
//     }

//     printf("Errors: %i, Error Margin: %li, Largest Error: %i \n", errors, error_margin, largest_error);
                        
//     printf("Base Elapsed time: %f seconds\n", time_spent_base);              
//     printf("Bar_Redu Elapsed time: %f seconds\n", time_spent);

//     test = mod_exp(3, 9, 7);
//     printf("%li \n", test);

//     return 0;
// }
