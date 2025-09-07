// =====================================================
// =====================================================
//
//
// This module incorporates an HDMI enable signal, allowing
// the user to switch from HDMI to VGA as needed. 
//
//
//
// =====================================================
// =====================================================
module display_interface #(
    parameter HDMI_EN = 1 // 0 = VGA, 1 = HDMI
)
    (
    input  wire        i_p_clk,
    input  wire        i_tmds_clk,
    input  wire        i_rstn,

    // frame buffer interface
    output reg  [18:0] o_raddr,
    input  wire [11:0] i_rdata,

    // HDMI TMDS out
    output wire [3:0]  o_TMDS_P,
    output wire [3:0]  o_TMDS_N,
    
    // VGA RGB data out
    output wire  [3:0]  o_vga_red,
    output wire [3:0]   o_vga_green,
    output wire [3:0]   o_vga_blue,
    
    // VGA syncs
    output wire         o_vga_hs,
    output wire         o_vga_vs
    );


// =============================================================
//              Parameters, Registers, and Wires
// =============================================================
    reg  [18:0] nxt_raddr;

    wire        vsync, hsync, active;
    wire [9:0]  counterX, counterY;
    reg  [7:0]  red, green, blue;
    
 
    reg  [1:0]  STATE, NEXT_STATE;
    localparam  STATE_INITIAL = 0,
                STATE_DELAY   = 1,
                STATE_IDLE    = 3,
                STATE_ACTIVE  = 2;


// =============================================================
//                    Implementation:
// =============================================================

    initial begin
        STATE = STATE_INITIAL;
    end

    // assign rgb
    always@(*) begin
        red   = i_rdata[11:8];
        green = i_rdata[7:4]; 
        blue  = i_rdata[3:0]; 
    end
    // next state combo logic
    always@(*) begin
        nxt_raddr  = o_raddr;
        NEXT_STATE = STATE;
        case(STATE)

            // wait 2 frames for camera configuration on reset/startup
            STATE_INITIAL: begin
                NEXT_STATE = ((counterX == 640) && (counterY == 480)) ? STATE_DELAY:STATE_INITIAL;
            end

            STATE_DELAY: begin
                NEXT_STATE = ((counterX == 640) && (counterY == 480)) ? STATE_ACTIVE:STATE_DELAY;
            end

            STATE_IDLE: begin
                if((counterX == 799)&&((counterY==524)||(counterY<480))) begin
                    nxt_raddr  = o_raddr + 1;
                    NEXT_STATE = STATE_ACTIVE;
                end
                else if(counterY > 479) begin
                    nxt_raddr = 0;
                end
            end

            // normal operation: begin reading from frame buffer at start of frame
            STATE_ACTIVE: begin
                if(active && (counterX < 639)) begin
                    nxt_raddr = (o_raddr == 307199) ? 0:o_raddr+1;
                end
                else begin
                    NEXT_STATE = STATE_IDLE;
                end
            end


        endcase
    end

    // registered logic
    always@(posedge i_p_clk) begin
        if(!i_rstn) begin
            o_raddr <= 0;
            STATE   <= STATE_INITIAL;
        end
        else begin
            o_raddr <= nxt_raddr;
            STATE   <= NEXT_STATE;
        end
    end

//
//
    vtc #(
    .COUNTER_WIDTH(10)
    )
    vtc_i (
    .i_clk         (i_p_clk  ), // pixel clock
    .i_rstn        (i_rstn   ), 

    // timing signals
    .o_vsync       (vsync    ),
    .o_hsync       (hsync    ),
    .o_active      (active   ),

    // counter passthrough
    .o_counterX    (counterX ),
    .o_counterY    (counterY )
    );
    
    // ====================================================
    //              Output Selection (Generate)
    // ====================================================
    
    assign o_vga_red   = (HDMI_EN) ? 4'b0   : o_vga_red;
    assign o_vga_green = (HDMI_EN) ? 4'b0   : o_vga_green;
    assign o_vga_blue  = (HDMI_EN) ? 4'b0   : o_vga_blue;
    assign o_vga_hs    = (HDMI_EN) ? 1'b0   : hsync;
    assign o_vga_vs    = (HDMI_EN) ? 1'b0   : vsync;
    
    assign o_TMDS_P    = (HDMI_EN) ? o_TMDS_P : 4'b0000;
    assign o_TMDS_N    = (HDMI_EN) ? o_TMDS_N : 4'b0000;
    
    generate
        if(HDMI_EN == 0) begin : g_vga
        // VGA path
            VGA_top VGA_i(
            .i_p_clk          (i_p_clk    ), // pixel clock
            .i_rstn           (i_rstn     ),
            
            .i_pixel          (i_rdata    ), // input RGB444 data
            
            // timing signals
            .i_vsync          (vsync      ),
            .i_hsync          (hsync      ),
            .i_active_area    (active     ),
            
            // VGA out
            .o_R              (o_vga_red  ),
            .o_G              (o_vga_green),
            .o_B              (o_vga_blue ),
            
            .o_HS             (o_vga_hs   ),
            .o_VS             (o_vga_vs   )
            );
        end
        else begin : g_hdmi
        // HDMI path
            HDMI_top HDMI_i (
            .i_p_clk       (i_p_clk    ), // pixel clock
            .i_tmds_clk    (i_tmds_clk ), // 10x pixel clock
            .i_resetn      (i_rstn     ),
        
            .i_pixel       (i_rdata    ),
        
            // Timing Signals in; from VTC
            .i_vsync       (vsync      ),
            .i_hsync       (hsync      ),
            .i_active_area (active     ),
        
            // HDMI TMDS out
            .o_TMDS_P      (o_TMDS_P   ),
            .o_TMDS_N      (o_TMDS_N   )
            );
        end
    endgenerate
endmodule
