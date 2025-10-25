`default_nettype none
`timescale 1ns / 1ps

package transformer_pkg;
    import math_pkg::*;
    import vertex_pkg::*;
 
    // Q16.16 multiply with 64-bit intermediate
    function automatic q16_16_t mul_transform(input q16_16_t a, input q16_16_t b);
        logic signed [27:0] a_round, b_round; // Q16.12
        logic signed [55:0] t;               // Q32.24

        a_round = a[31:4];
        b_round = b[31:4];
        t = a_round * b_round;
        return q16_16_t'(t >>> 8);
    endfunction

    function automatic point3d_t add_3d_transform(input point3d_t a, input point3d_t b);
        point3d_t result;
        result.x = a.x + b.x;
        result.y = a.y + b.y;
        result.z = a.z + b.z;
        return result;
    endfunction


    // Dot product row·vec, row & vec in Q16.16; accumulate wide, single >>>16
    function automatic q16_16_t dot3_transform(
        input q16_16_t ax, input q16_16_t ay, input q16_16_t az,
        input q16_16_t bx, input q16_16_t by, input q16_16_t bz
    );
        logic signed [27:0] ax_round, ay_round, az_round; // Q16.12
        logic signed [27:0] bx_round, by_round, bz_round; // Q16.12

        logic signed [55:0] p0, p1, p2; // Q32.24
        logic signed [55:0] sum;        // Q32.24
        
        ax_round = ax[31:4]; ay_round = ay[31:4]; az_round = az[31:4];
        bx_round = bx[31:4]; by_round = by[31:4]; bz_round = bz[31:4];
        
        p0  = ax_round * bx_round; // Q32.24
        p1  = ay_round * by_round; // Q32.24
        p2  = az_round * bz_round; // Q32.24

        sum = p0 + p1 + p2; // Q32.24   

        return q16_16_t'(sum >>> 8);
    endfunction

    typedef struct packed {
        triangle_t triangle;
        transform_t model_transform;
        transform_t camera_transform;
        logic model_transform_valid;
        logic camera_transform_valid;
    } transform_setup_t;

    typedef struct packed {
        q16_16_t R11;
        q16_16_t R12;
        q16_16_t R13;
        q16_16_t R21;
        q16_16_t R22;
        q16_16_t R23;
        q16_16_t R31;
        q16_16_t R32;
        q16_16_t R33;
    } matrix_t;

    typedef struct packed {
        point3d_t pos;
        matrix_t  rot_mtx;  // rotation matix
        point3d_t scale;
    } matrix_transform_t;

    typedef struct packed {
        triangle_t triangle;
            matrix_transform_t model;
        matrix_transform_t camera;
    } model_world_t;

    typedef struct packed {
        triangle_t triangle;
        matrix_transform_t camera;
    } world_camera_t;
endpackage