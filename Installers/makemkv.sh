#!/usr/bin/env bash
set -euo pipefail

read -p "Build MakeMKV + custom FFmpeg? (y/n): " ans
[[ "$ans" =~ ^[Yy]$ ]] || exit

# Dependencies
sudo pacman -S --needed base-devel openssl expat qt5-base zlib nasm \
  gcc-libs ffmpeg x264 x265 libvpx opus

# Optional: libfdk_aac is nonfree — need ffmpeg compiled with it
# So skip system ffmpeg and compile custom below

# Prepare temp
TMP=$(mktemp -d)
cd "$TMP"

echo "Building ffmpeg..."
# Build FFmpeg with extended codecs
FFMPEG_VERSION=7.1.1
curl -LO https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2
tar -xjf ffmpeg-${FFMPEG_VERSION}.tar.bz2
cd ffmpeg-${FFMPEG_VERSION}
./configure \
  --prefix="$TMP/ffmpeg" --enable-static --disable-shared --enable-pic \
  --enable-gpl --enable-nonfree --enable-libfdk_aac \
  --enable-libx264 --enable-libx265 --enable-libvpx --enable-libopus
make -j"$(nproc)"
make install
cd ..

echo "Building Makemkv..."
# Build MakeMKV OSS + Binary
VERSION=1.18.1
curl -LO https://www.makemkv.com/download/makemkv-oss-${VERSION}.tar.gz
curl -LO https://www.makemkv.com/download/makemkv-bin-${VERSION}.tar.gz
tar xf makemkv-oss-${VERSION}.tar.gz
tar xf makemkv-bin-${VERSION}.tar.gz

cd makemkv-oss-${VERSION}
PKG_CONFIG_PATH=$TMP/ffmpeg/lib/pkgconfig ./configure
make -j"$(nproc)"
sudo make install
cd ..

cd makemkv-bin-${VERSION}
make -j"$(nproc)"
sudo make install
cd ..

# Cleanup
cd ~
rm -rf "$TMP"

echo "Done: MakeMKV + custom FFmpeg installed."
