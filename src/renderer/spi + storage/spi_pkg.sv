package opcode_defs;
    localparam logic [3:0] OP_WIPE_ALL    = 4'b0000;
    localparam logic [3:0] OP_CREATE_VERT = 4'b0001;
    localparam logic [3:0] OP_CREATE_TRI  = 4'b0010;
    localparam logic [3:0] OP_CREATE_INST = 4'b0011;
    localparam logic [3:0] OP_UPDATE_INST = 4'b0100;
    localparam logic [3:0] RESERVED       = 4'b0101;
endpackage

package status_defs;
    typedef enum logic [3:0] {
        INVALID_DATA   = 4'b0000,
        OK             = 4'b0001,
        OUT_OF_MEMORY  = 4'b0010, // 2
        INVALID_ID     = 4'b0011, // 3
        INVALID_OPCODE = 4'b0100, // 4
        BUFFER_FULL    = 4'b0101  // 5
    } status_e;
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
   
    typedef struct packed { 
        logic [7:0] vert_id;
        logic [7:0] tri_id;
    } inst_desc_t;
endpackage