# dazed
Dazed is an eink display driver for the reMarkable 2.

## building
The project is built using the [Zig language](https://ziglang.org/) so you'll need a working [Zig 0.13.0 install](https://ziglang.org/learn/getting-started/).

Note that if you want to build the emulator you must have SDL3 installed on your system. 
```
$ # In the project directory

$ zig build -Doptimize=ReleaseFast # build for the reMarkable 2
$ zig build -Doptimize=ReleaseFast -Demulator # build for the emulator
```
Then you can copy the binary `zig-out/bin/dazed` to the rM2 using ssh, or if you built the emulator run the binary directly.

## Thanks to:
- Mattéo Delabre for working on [waved](https://github.com/matteodelabre/waved) and making this project possible
- ghostty-org for making easily integrable Zig packages and all the developers of those libraries (living in pkg/)
- SDL developers for making an amazing library
- Zig Software Foundation for creating [Zig](https://ziglang.org/)
- reMarkable for making the reMarkable 2


## Screenshots
![PXL_20250225_214505545](https://github.com/user-attachments/assets/1671aa3d-e9b6-4c65-ad4b-2d8199caa19b)
