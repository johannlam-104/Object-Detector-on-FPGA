# Red-Object-Detector-on-FPGA-Using-OV7670-Camera-and-HDMI-Output
In development, done on Nexys A7

## This project builds on the open sourced HDMI video pipeline project linked here. LINK. My modifications focused on real-time red object detection logic
The aim for this project is to detect a red object and overlay a green crosshair over ov7670 camera feed, and be displayed on a HDMI monitor using TMDS encoding

### Features:
-RGB444 thresholding
-3x3 convolution kernels
-centroid calculation
-HDMI (TMDS Encoding)

### Block Diagrams
