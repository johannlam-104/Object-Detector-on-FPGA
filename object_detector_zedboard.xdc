# =============================================================================
# ZedBoard XDC - Camera (JA/JB), VGA, and Two Clocking Wizards
#   - clk_wiz_tmds  instance: dcm_i_0   (.clk_tmds -> 250 MHz, .clk_PS -> 100 MHz)
#   - clk_wiz_pix   instance: dcm_i_1   (.clk_24MHz -> o_cam_xclk, .clk_25MHz -> pix clk)
# =============================================================================

# -----------------------------------------------------------------------------
# Primary Board Clock (100 MHz)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN Y9 [get_ports {i_sysclk}]     ;# "GCLK"
create_clock -name clk_in100 -period 10.000 [get_ports i_sysclk]

# -----------------------------------------------------------------------------
# External Camera PCLK (input from sensor)
# -----------------------------------------------------------------------------
# Period ~41.167 ns (≈24.3 MHz). Adjust if your actual PCLK differs.
create_clock -name cam_pclk -period 41.167 -waveform {0.000 20.584} [get_ports i_cam_pclk]

# -----------------------------------------------------------------------------
# Generated clocks (from the two Clocking Wizards)
#   dcm_i_0: clk_wiz_tmds  -> clk_tmds (250 MHz), clk_PS (100 MHz)
#   dcm_i_1: clk_wiz_pix   -> clk_24MHz (to port o_cam_xclk), clk_25MHz (internal)
# -----------------------------------------------------------------------------

# --- Wizard #0: TMDS/Processing clocks (derived from i_sysclk) ---
create_generated_clock -name tmds_clk_250 \
  -source [get_clocks clk_in100] \
  [get_pins dcm_i_0/clk_tmds]

create_generated_clock -name sys_clk_100 \
  -source [get_clocks clk_in100] \
  [get_pins dcm_i_0/clk_PS]

# --- Wizard #1: Pixel (25 MHz) and Camera XCLK (24 MHz) (derived from i_sysclk) ---
create_generated_clock -name pix_clk_25 \
  -source [get_clocks clk_in100] \
  [get_pins dcm_i_1/clk_25MHz]

# Drive to the sensor; define the clock object on the top-level port.
create_generated_clock -name cam_xclk_24 \
  -source [get_clocks clk_in100] \
  [get_ports o_cam_xclk]

# -----------------------------------------------------------------------------
# Clock domain relationships
# -----------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group [get_clocks cam_pclk] \
  -group [get_clocks {sys_clk_100 tmds_clk_250}] \
  -group [get_clocks {pix_clk_25 cam_xclk_24}]

# -----------------------------------------------------------------------------
# JA Pmod - Camera Data in
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN Y11  [get_ports {i_cam_data[0]}]  ;# "JA1"
set_property PACKAGE_PIN AA11 [get_ports {i_cam_data[1]}]  ;# "JA2"
set_property PACKAGE_PIN Y10  [get_ports {i_cam_data[2]}]  ;# "JA3"
set_property PACKAGE_PIN AA9  [get_ports {i_cam_data[3]}]  ;# "JA4"
set_property PACKAGE_PIN AB11 [get_ports {i_cam_data[4]}]  ;# "JA7"
set_property PACKAGE_PIN AB10 [get_ports {i_cam_data[5]}]  ;# "JA8"
set_property PACKAGE_PIN AB9  [get_ports {i_cam_data[6]}]  ;# "JA9"
set_property PACKAGE_PIN AA8  [get_ports {i_cam_data[7]}]  ;# "JA10"

# -----------------------------------------------------------------------------
# JB Pmod - Camera control signals
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN W12 [get_ports {o_cam_xclk}]  ;# "JB1"
set_property PACKAGE_PIN W11 [get_ports {o_cam_rstn}]  ;# "JB2"
set_property PACKAGE_PIN V10 [get_ports {o_cam_pwdn}]  ;# "JB3"
set_property PACKAGE_PIN W8  [get_ports {i_cam_pclk}]  ;# "JB4"
set_property PACKAGE_PIN V12 [get_ports {i_cam_vsync}] ;# "JB7"
set_property PACKAGE_PIN W10 [get_ports {i_cam_href}]  ;# "JB8"
set_property PACKAGE_PIN V9  [get_ports {SCL}]         ;# "JB9"
set_property PACKAGE_PIN V8  [get_ports {SDA}]         ;# "JB10"

# -----------------------------------------------------------------------------
# VGA Output - Bank 33
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN Y21  [get_ports {o_blue[0]}]  ;# "VGA-B1"
set_property PACKAGE_PIN Y20  [get_ports {o_blue[1]}]  ;# "VGA-B2"
set_property PACKAGE_PIN AB20 [get_ports {o_blue[2]}]  ;# "VGA-B3"
set_property PACKAGE_PIN AB19 [get_ports {o_blue[3]}]  ;# "VGA-B4"
set_property PACKAGE_PIN AB22 [get_ports {o_green[0]}] ;# "VGA-G1"
set_property PACKAGE_PIN AA22 [get_ports {o_green[1]}] ;# "VGA-G2"
set_property PACKAGE_PIN AB21 [get_ports {o_green[2]}] ;# "VGA-G3"
set_property PACKAGE_PIN AA21 [get_ports {o_green[3]}] ;# "VGA-G4"
set_property PACKAGE_PIN AA19 [get_ports {o_hs}]       ;# "VGA-HS"
set_property PACKAGE_PIN V20  [get_ports {o_red[0]}]   ;# "VGA-R1"
set_property PACKAGE_PIN U20  [get_ports {o_red[1]}]   ;# "VGA-R2"
set_property PACKAGE_PIN V19  [get_ports {o_red[2]}]   ;# "VGA-R3"
set_property PACKAGE_PIN V18  [get_ports {o_red[3]}]   ;# "VGA-R4"
set_property PACKAGE_PIN Y19  [get_ports {o_vs}]       ;# "VGA-VS"

# -----------------------------------------------------------------------------
# User Push Button
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN P16 [get_ports {i_rst}]       ;# "BTNC"

# -----------------------------------------------------------------------------
# Power / I/O Standards
#   Bank 33 fixed 3.3V (VGA), Bank 13 fixed 3.3V (PMODs),
#   Banks 34/35 set to 1.8V by default.
# -----------------------------------------------------------------------------
set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 33]]
set_property IOSTANDARD LVCMOS18 [get_ports -of_objects [get_iobanks 34]]
set_property IOSTANDARD LVCMOS18 [get_ports -of_objects [get_iobanks 35]]
set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 13]]
