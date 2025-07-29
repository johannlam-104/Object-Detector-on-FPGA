# Red-Object-Detector-on-FPGA-Using-OV7670-Camera-and-HDMI-Output
In development, done on zedboard

## This project builds on the open sourced HDMI video pipeline project linked here. [LINK](https://github.com/georgeyhere/FPGA-Video-Processing/tree/master). My modifications focused on real-time red object detection logic. Opened sourced code is in the src folder, my mods are in the my_mods folder. Also modified kernel control module to include bottom row padding
The aim for this project is to detect a red object and overlay a green crosshair over ov7670 camera feed, and be displayed on a HDMI monitor using TMDS encoding

### Features:
-RGB444 thresholding
-3x3 convolution kernels
-centroid calculation
-HDMI (TMDS Encoding)
-axi stream interface enabling handshaking of pixel data

### Block Diagrams
## Processing overview (This original block diagram had a fundamental error with muxing between the two data paths)
<img width="863" height="398" alt="image" src="https://github.com/user-attachments/assets/b5ec4725-845f-411c-bbf8-6b2e76755f35" />


## New architecture
<img width="753" height="273" alt="image" src="https://github.com/user-attachments/assets/c8a80c85-481e-4bcf-96ee-2940b5526825" />

