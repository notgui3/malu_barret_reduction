#include <stdio.h>
#include <math.h>
#include <stdlib.h>

long bar_redu(long a, long n){
    long base = 2;
    long k = (log(a)/log(base)) + 1;
    long b_k = pow(base, 2*k);

    // long b_k = 1;

    // while (k > 0) {

    //     if ((k % 2) == 1) {
    //       b_k *= base;  
    //     } 
        
    //     base *= base;
    //     k /= 2;
    // }

    long m = (b_k)/n;
    long q = ((a/(pow(base, k-1)))*m)/(pow(base, k+1));

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

long mod_k(long base, long ko, long n) {
    long b = bar_redu(base, n);
    long b_kult = 1;

    long e = ko;

    while (e > 0){

        if(mod(e, 2) == 1){
            b_kult = mod_mul(b_kult, b, n);
        }

        b = mod_mul(b, b, n);

        e = e/2;
    }

    return b_kult;
}

long main(void){

    long test = mod_mul(20, 10, 7);
    printf("%li \n", test);

    int errors = 0;
    long error_margin = 0;
    int largest_error = 0;
    for(long i = 1; i < 20000; i++){
        for(long j = 1; j < 20000; j++){
            // printf("Loop %li, %li", i, j);
            long diff = abs( (int) ((i%j) - bar_redu(i,j)));
            // printf("%li \n", diff);
            if( diff != 0 ){
                errors++;
                error_margin += diff;
            }
            if(diff > largest_error){
                largest_error = diff;
            }
        }
    }
    printf("Errors: %i, Error Margin: %li, Largest Error: %i \n", errors, error_margin, largest_error);

    test = mod_k(3, 9, 7);
    printf("%li \n", test);

    return 0;
}
