# Cross-compiling FFmpeg for Windows Static Libraries on macOS (with PNG Support)

This guide walks through the process of cross-compiling FFmpeg static libraries for Windows while working on macOS, including PNG and h264 support.

## Prerequisites

Install required tools using Homebrew:

```bash
brew install mingw-w64
brew install yasm
brew install pkg-config
brew install make
brew install nasm
```

## Building x264

First, we need to build x264 for Windows:

```bash
# Create and enter build directory
mkdir x264-build && cd x264-build

# Clone x264
git clone https://code.videolan.org/videolan/x264.git
cd x264

# Configure and build x264
./configure --host=x86_64-w64-mingw32 --cross-prefix=x86_64-w64-mingw32- \
  --prefix=/usr/local/x86_64-w64-mingw32 --enable-static --disable-cli

# Build and install (requires sudo for install)
make -j$(sysctl -n hw.ncpu)
sudo make install
cd ../..
```

## Building zlib (Required for PNG Support)

Before building FFmpeg, we need to build zlib for Windows:

```bash
# Create and enter a build directory for zlib
mkdir zlib-build && cd zlib-build

# Download and extract zlib
curl -O https://zlib.net/zlib-1.3.1.tar.gz
tar xzf zlib-1.3.1.tar.gz
cd zlib-1.3.1

# Configure and build zlib for MinGW
CROSS_PREFIX=x86_64-w64-mingw32- ./configure --prefix=/usr/local/x86_64-w64-mingw32 --static

# Build
make -j$(sysctl -n hw.ncpu)

# Create the static library using MinGW ar instead of libtool
x86_64-w64-mingw32-ar rcs libz.a adler32.o crc32.o deflate.o infback.o inffast.o inflate.o inftrees.o trees.o zutil.o compress.o uncompr.o gzclose.o gzlib.o gzread.o gzwrite.o

# Install
sudo make install
cd ../..
```

## Setting up pkg-config

Create a custom pkg-config wrapper for MinGW:

```bash
sudo bash -c 'cat > /usr/local/bin/x86_64-w64-mingw32-pkg-config << '\''EOF'\''
#!/bin/sh
export PKG_CONFIG_LIBDIR=/usr/local/x86_64-w64-mingw32/lib/pkgconfig:/usr/local/x86_64-w64-mingw32/lib64/pkgconfig
export PKG_CONFIG_PATH=
pkg-config "$@"
EOF'

sudo chmod +x /usr/local/bin/x86_64-w64-mingw32-pkg-config
```

## Building OpenSSL

Before building FFmpeg, we need to build OpenSSL for Windows:

```bash
# Create and enter build directory
mkdir openssl-build && cd openssl-build

# Download OpenSSL
curl -L -O https://github.com/openssl/openssl/releases/download/openssl-3.4.1/openssl-3.4.1.tar.gz
tar xzf openssl-3.4.1.tar.gz
cd openssl-3.4.1

# Configure OpenSSL for MinGW
./Configure mingw64 --cross-compile-prefix=x86_64-w64-mingw32- \
  --prefix=/usr/local/x86_64-w64-mingw32 \
  no-shared no-async

# Build and install
make -j$(sysctl -n hw.ncpu)
sudo make install
cd ../..
```

## Building FFmpeg

Now we can build FFmpeg with exactly what we need for screen capture and RTMP streaming:

```bash
# Clone FFmpeg
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg

# Configure FFmpeg
LDFLAGS="-lws2_32 -lgdi32 -lcrypt32" \
PKG_CONFIG_PATH="/usr/local/x86_64-w64-mingw32/lib64/pkgconfig" \
CFLAGS="-DWIN32_LEAN_AND_MEAN -DHAVE_WIN32_THREADS=1 -DPTW32_STATIC_LIB -D_WIN32_WINNT=0x0601" \
./configure \
  --pkg-config-flags="--static" \
  --prefix=./windows-build \
  --arch=x86_64 \
  --target-os=mingw32 \
  --cross-prefix=x86_64-w64-mingw32- \
  --pkg-config=x86_64-w64-mingw32-pkg-config \
  --enable-cross-compile \
  --enable-static \
  --disable-shared \
  --disable-doc \
  --disable-postproc \
  --disable-programs \
  --enable-gpl \
  --enable-nonfree \
  --enable-libx264 \
  --enable-avdevice \
  --enable-w32threads \
  --disable-pthreads \
  --enable-network \
  --enable-zlib \
  --enable-swscale \
  --enable-protocol=file \
  --enable-protocol=tcp \
  --enable-protocol=rtmp \
  --enable-protocol=rtmpe \
  --enable-protocol=rtmps \
  --enable-protocol=rtmpt \
  --enable-demuxer=rtmp \
  --enable-muxer=rtmp \
  --enable-demuxer=flv \
  --enable-muxer=flv \
  --enable-protocol=http \
  --enable-protocol=https \
  --enable-openssl \
  --enable-protocol=tls \
  --enable-protocol=udp \
  --enable-encoder=png \
  --enable-decoder=png \
  --enable-indev=gdigrab \
  --enable-encoder=libx264 \
  --extra-ldflags="-static"

# Build FFmpeg
make clean
make -j$(sysctl -n hw.ncpu)
make install

## Output Files

After successful compilation, you'll find the static libraries in `./windows-build/lib`:

- libavcodec.a
- libavformat.a
- libavutil.a
- libswresample.a
- libswscale.a

The header files will be in `./windows-build/include/`.

## Configuration Notes

The configuration above includes:
- H.264 encoding/decoding (via libx264)
- PNG image support with resizing capabilities
- RTMP streaming support
- Static libraries only (no DLLs)
- Minimal build with only necessary components enabled

## Important Notes

1. The `-include stdint.h` CFLAG is crucial for the build to succeed
2. Make sure all the paths in the pkg-config wrapper match your system
3. The build is specifically for x86_64 Windows targets
4. For PNG support, we use the image2 demuxer/muxer instead of specific PNG demuxer/muxer
5. When building zlib, using MinGW's ar tool instead of macOS's libtool is essential

## Troubleshooting

1. Verify x264 is properly installed:
   ```bash
   ls -l /usr/local/x86_64-w64-mingw32/lib/libx264.a
   ls -l /usr/local/x86_64-w64-mingw32/include/x264.h
   ```

2. Verify zlib is properly installed:
   ```bash
   ls -l /usr/local/x86_64-w64-mingw32/lib/libz.a
   ls -l /usr/local/x86_64-w64-mingw32/include/zlib.h
   ```

3. Test pkg-config setup:
   ```bash
   x86_64-w64-mingw32-pkg-config --list-all
   x86_64-w64-mingw32-pkg-config --libs x264
   ```

4. If modifying the configuration, always run `make clean` before rebuilding