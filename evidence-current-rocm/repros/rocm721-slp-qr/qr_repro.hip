#include <hip/hip_runtime.h>
#define WP_NO_BFLOAT16
#define WP_TILE_BLOCK_DIM 256
#include "builtin.h"
// /mnt/data/melliott/moat-testing/projects/warp/warp/_src/optim/linear.py:0
static CUDA_CALLABLE void _qr_decomposition_0(
    wp::mat_t<10, 10, wp::float32> var_A,
    wp::mat_t<10, 10, wp::float32> & ret_0,
    wp::mat_t<10, 10, wp::float32> & ret_1)
{
    //---------
    // primal vars
    const wp::int32 var_0 = 0;
    wp::vec_t<10, wp::float32> var_1;
    wp::vec_t<10, wp::float32> var_2;
    wp::mat_t<10, 10, wp::float32> var_3;
    const wp::float32 var_4 = 0.0;
    wp::float32 var_5;
    const wp::float32 var_6 = 2.0;
    wp::float32 var_7;
    wp::int32 var_8;
    wp::int32 var_9;
    wp::int32 var_10;
    wp::int32 var_11;
    bool var_12;
    wp::float32 var_13;
    wp::float32 var_14;
    wp::float32 var_15;
    wp::float32 var_16;
    wp::float32 var_17;
    wp::float32 var_18;
    bool var_19;
    wp::float32 var_20;
    wp::float32 var_21;
    wp::float32 var_22;
    wp::vec_t<10, wp::float32> var_23;
    wp::vec_t<10, wp::float32> var_24;
    wp::mat_t<10, 10, wp::float32> var_25;
    wp::mat_t<10, 10, wp::float32> var_26;
    wp::vec_t<10, wp::float32> var_27;
    wp::vec_t<10, wp::float32> var_28;
    wp::mat_t<10, 10, wp::float32> var_29;
    wp::mat_t<10, 10, wp::float32> var_30;
    //---------
    // forward
    // def _qr_decomposition(A: Any):                                                         <L 1>
    // x = type(A[0])()                                                                       <L 6>
    var_1 = wp::extract(var_A, var_0);
    var_2 = wp::vec_t<10, wp::float32>();
    // Q = wp.identity(n=x.length, dtype=A.dtype)                                             <L 7>
    var_3 = wp::identity<10, wp::float32>();
    // zero = x.dtype(0.0)                                                                    <L 9>
    var_5 = wp::float32(var_4);
    // two = x.dtype(2.0)                                                                     <L 10>
    var_7 = wp::float32(var_6);
    // for i in range(x.length):                                                              <L 12>
    var_8 = 0;
    start_for_0:;
        if (var_8 >= 10) goto end_for_0;
        var_9 = var_8;
        var_8 += 1;
        // for k in range(x.length):                                                          <L 13>
        var_10 = 0;
        start_for_2:;
            if (var_10 >= 10) goto end_for_2;
            var_11 = var_10;
            var_10 += 1;
            // x[k] = wp.where(k < i, zero, A[k, i])                                          <L 14>
            var_12 = (var_11 < var_9);
            var_13 = wp::extract(var_A, var_11, var_9);
            var_14 = wp::where(var_12, var_5, var_13);
            wp::assign_inplace(var_2, var_11, var_14);
            goto start_for_2;
        end_for_2:;
        // alpha = wp.length(x) * wp.sign(x[i])                                               <L 16>
        var_15 = wp::length(var_2);
        var_16 = wp::extract(var_2, var_9);
        var_17 = wp::sign(var_16);
        var_18 = wp::mul(var_15, var_17);
        // x[i] += alpha                                                                      <L 17>
        wp::add_inplace(var_2, var_9, var_18);
        // two_over_x_sq = wp.where(alpha == zero, zero, two / wp.length_sq(x))               <L 18>
        var_19 = (var_18 == var_5);
        var_20 = wp::length_sq(var_2);
        var_21 = wp::div(var_7, var_20);
        var_22 = wp::where(var_19, var_5, var_21);
        // A -= wp.outer(two_over_x_sq * x, x * A)                                            <L 20>
        var_23 = wp::mul(var_22, var_2);
        var_24 = wp::mul(var_2, var_A);
        var_25 = wp::outer(var_23, var_24);
        var_26 = wp::sub(var_A, var_25);
        // Q -= wp.outer(Q * x, two_over_x_sq * x)                                            <L 21>
        var_27 = wp::mul(var_3, var_2);
        var_28 = wp::mul(var_22, var_2);
        var_29 = wp::outer(var_27, var_28);
        var_30 = wp::sub(var_3, var_29);
        wp::assign(var_A, var_26);
        wp::assign(var_3, var_30);
        goto start_for_0;
    end_for_0:;
    // return Q, A                                                                            <L 23>
    ret_0 = var_3;
    ret_1 = var_A;
    return;
}

__global__ void qr_kernel(const wp::mat_t<10, 10, wp::float32>* a, wp::mat_t<10, 10, wp::float32>* q, wp::mat_t<10, 10, wp::float32>* r, int n)
{
    int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= n) return;
    _qr_decomposition_0(a[t], q[t], r[t]);
}

#include <cstdio>
#include <cmath>
#include <vector>
int main()
{
    const int n = 4, N = 10;
    using M = wp::mat_t<10, 10, wp::float32>;
    std::vector<M> a(n), q(n), r(n), qh(n), rh(n);
    unsigned s = 12345;
    for (int b = 0; b < n; ++b) {
        float C[10][10];
        for (int i = 0; i < N; ++i) for (int j = 0; j < N; ++j) { s = s * 1664525u + 1013904223u; C[i][j] = (s >> 8) / 16777216.0f * 2.f - 1.f; }
        for (int i = 0; i < N; ++i) for (int j = 0; j < N; ++j) { float v = (i == j) ? 10.f : 0.f; for (int k = 0; k < N; ++k) v += C[i][k] * C[j][k]; a[b].data[i][j] = v; }
        _qr_decomposition_0(a[b], qh[b], rh[b]);  // host reference, same code
    }
    M *da, *dq, *dr;
    hipMalloc(&da, n * sizeof(M)); hipMalloc(&dq, n * sizeof(M)); hipMalloc(&dr, n * sizeof(M));
    hipMemcpy(da, a.data(), n * sizeof(M), hipMemcpyHostToDevice);
    qr_kernel<<<1, 64>>>(da, dq, dr, n);
    hipMemcpy(q.data(), dq, n * sizeof(M), hipMemcpyDeviceToHost);
    hipMemcpy(r.data(), dr, n * sizeof(M), hipMemcpyDeviceToHost);
    float dmax = 0.f;
    for (int b = 0; b < n; ++b) for (int i = 0; i < N; ++i) for (int j = 0; j < N; ++j)
        dmax = fmaxf(dmax, fmaxf(fabsf(q[b].data[i][j] - qh[b].data[i][j]), fabsf(r[b].data[i][j] - rh[b].data[i][j])));
    printf("max |device - host| = %g\n", dmax);
    return dmax > 1e-3f;
}
