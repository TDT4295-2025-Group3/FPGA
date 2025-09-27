

//package transform_pkg;
//    typedef struct packed {
//        logic [32-1:0] posx;
//        logic [32-1:0]posy;
//        logic [32-1:0]posz;
//        logic [32-1:0] rotx;
//        logic [32-1:0]roty;
//        logic [32-1:0]rotz;
//        logic [32-1:0] scalex;
//        logic [32-1:0]scaley;
//        logic [32-1:0]scalez;
//    } transf_t;

//endpackage

//package buffer_id_pkg;

//    typedef struct packed {
//        logic [32-1:0]posx;
//        logic [32-1:0]posy;
//        logic [32-1:0]posz;
//        logic [32-1:0]rotx;
//        logic [32-1:0]roty;
//        logic [32-1:0]rotz;
//        logic [32-1:0]scalex;
//        logic [32-1:0]scaley;
//        logic [32-1:0]scalez;
//        logic [$clog2(MAX_VERT_BUF)-1:0] vert_id;
//        logic [$clog2(MAX_VERT_BUF)-1:0] tri_id;
//    } inst_t;

//    typedef struct packed {
//        logic [$clog2(MAX_VERT)-1:0]  base;
//        logic [VIDX_W-1:0]            count;
//    } vert_desc_t;
    
//    typedef struct packed {
//        logic [$clog2(MAX_TRI)-1:0]   base;
//        logic [TIDX_W-1:0]            count;
//    } tri_desc_t;
//endpackage

package opcode_defs;
    localparam logic [3:0] OP_WIPE_ALL    = 4'b0000;
    localparam logic [3:0] OP_CREATE_VERT = 4'b0001;
    localparam logic [3:0] OP_CREATE_TRI  = 4'b0010;
    localparam logic [3:0] OP_CREATE_INST = 4'b0011;
    localparam logic [3:0] OP_UPDATE_INST = 4'b0100;
endpackage

module pkg();
endmodule