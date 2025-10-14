

// transform use 32 * 4*3 = 384
package transform_pkg; 
   import math_pkg::point3d_t;
   typedef struct packed {
        point3d_t pos;
        point3d_t sin_rot;
        point3d_t cos_rot;
        point3d_t scale;
   } transform_t;
endpackage

// insetance use 32 * 4*3 + 8 * 2 = 400
package buffer_id_pkg;
   import math_pkg::point3d_t;
   typedef struct packed {
        point3d_t pos;
        point3d_t sin_rot;
        point3d_t cos_rot;
        point3d_t scale;
        logic [8-1:0] vert_id;  // Max 256 distinct buffers
        logic [8-1:0] tri_id;
   } inst_t;

   typedef struct packed {
        logic [13-1:0]  base;    // Max vertices 8192 
        logic [8-1:0]   count;
   } vert_desc_t;
    
   typedef struct packed {
        logic [13-1:0]   base;
        logic [8-1:0]    count;
   } tri_desc_t;
endpackage


package vertex_pkg;
    import math_pkg::point3d_t;
    import color_pkg::color12_t;

    typedef struct packed {
        point3d_t pos;
        color12_t color;
    } vertex_t;

    typedef struct packed {
        vertex_t v0;
        vertex_t v1;
        vertex_t v2;
    } triangle_t;

endpackage


package opcode_defs;
    localparam logic [3:0] OP_IDLE        = 4'b0000;
    localparam logic [3:0] OP_CREATE_VERT = 4'b0001;
    localparam logic [3:0] OP_CREATE_TRI  = 4'b0010;
    localparam logic [3:0] OP_CREATE_INST = 4'b0011;
    localparam logic [3:0] OP_UPDATE_INST = 4'b0100;
    localparam logic [3:0] WIPE_ALL       = 4'b0101;
endpackage

package status_defs;
    localparam logic [3:0] INVALID_DATA   = 4'b0000;
    localparam logic [3:0] OK             = 4'b0001;
    localparam logic [3:0] OUT_OF_MEMORY  = 4'b0010;
    localparam logic [3:0] INVALID_ID     = 4'b0011;
    localparam logic [3:0] INVALID_OPCODE = 4'b0100;
    localparam logic [3:0] BUFFER_FULL    = 4'b0101;

endpackage

module pkg();
endmodule   