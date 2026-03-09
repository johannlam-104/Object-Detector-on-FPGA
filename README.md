# Red-Object-Detector-on-FPGA-Using-OV7670-Camera-and-VGA-Output
The aim for this project is to detect a red object and overlay a green crosshair over ov7670 camera feed, and be displayed on a VGA monitor

## Live Hardware Demo
https://youtu.be/-TX4hx-_ViQ 

## This project builds on the open sourced HDMI video pipeline project linked [here](https://github.com/georgeyhere/FPGA-Video-Processing/tree/master). My modifications focused on real-time red object detection logic and frame buffering

## Block Diagrams

## Final Processing Core
<img width="1747" height="684" alt="Block Diagram" src="https://github.com/user-attachments/assets/c7b9ef6d-8092-4287-86e4-ca9600ac11a8" />

## Camera module (open sourced)
## modifications: implemented AXI-Stream output and TLAST/TUSER metadata generation
<img width="1117" height="618" alt="image" src="https://github.com/user-attachments/assets/bbcfe919-c518-4c60-bc8f-36ba054f5f2a" />

## System Level Top
<img width="1050" height="555" alt="image" src="https://github.com/user-attachments/assets/e3daba7e-b3a0-4db3-a586-effdbd144ab1" />

## Video Demo (Version 1.0)
https://youtu.be/ILm-690KBs4 
# working on VDMA bring up for full resolution buffering without shearing

## Block design
<img width="2267" height="1099" alt="image" src="https://github.com/user-attachments/assets/15cb0c02-cf0c-4d6d-b730-c532b4a3d810" />


