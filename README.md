# Red-Object-Detector-on-FPGA-Using-OV7670-Camera-and-HDMI-Output
The aim for this project is to detect a red object and overlay a green crosshair over ov7670 camera feed, and be displayed on a VGA monitor via HDMI using TMDS encoding

## This project builds on the open sourced HDMI video pipeline project linked [here](https://github.com/georgeyhere/FPGA-Video-Processing/tree/master). My modifications focused on real-time red object detection logic with the addition of a couple minor changes to open sourced modules and an HDMI enable that allows the user to switch between HDMI and VGA display in case their board does not offer HDMI

## Block Diagrams

## Final Processing Core
<img width="1747" height="684" alt="Block Diagram" src="https://github.com/user-attachments/assets/c7b9ef6d-8092-4287-86e4-ca9600ac11a8" />

  ### Design Iteration
  This diagram had a fundamental error with muxing between the 2 data paths
  <img width="863" height="398" alt="image" src="https://github.com/user-attachments/assets/b5ec4725-845f-411c-bbf8-6b2e76755f35" />

## Camera module (open sourced)
<img width="1117" height="618" alt="image" src="https://github.com/user-attachments/assets/bbcfe919-c518-4c60-bc8f-36ba054f5f2a" />

## System Level Top
<img width="1050" height="555" alt="image" src="https://github.com/user-attachments/assets/e3daba7e-b3a0-4db3-a586-effdbd144ab1" />


