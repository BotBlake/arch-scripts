#!/usr/bin/env bash
set -euo pipefail

read -rp "Build MakeMKV + custom FFmpeg with FDK-AAC? (y/n): " ans
[[ "$ans" =~ ^[Yy]$ ]] || exit 0

if (( EUID == 0 )); then
    echo "Run this script as a normal user; it will use sudo where required." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Versions + verified hashes
# ---------------------------------------------------------------------------

MAKEMKV_VERSION=2.0.0
FFMPEG_VERSION=9.0.2

# Official MakeMKV hashes:
# https://www.makemkv.com/download/makemkv-sha-2.0.0.txt
MAKEMKV_OSS_SHA256="435316b2d219eb48c880526557addd076b5f5e6de5171424c7651f9cac95b161"
MAKEMKV_BIN_SHA256="f1265e74875a186efdfbbbec7459a64e969033515e53cbc4d805f0a374f0a124"

# FFmpeg 9.0.2 tar.xz
FFMPEG_SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"

# FFmpeg 9 compatibility patch.
PATCH_URL="https://raw.githubusercontent.com/negativo17/makemkv/master/makemkv-ffmpeg9.patch"
PATCH_SHA256="fabb44600917cad50614cb368d4b3da6b8dd8ef97deb8d6135126dbbc79fb982"

JOBS="${JOBS:-$(nproc)}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fetch() {
    local url=$1
    local output=$2

    curl \
        --fail \
        --location \
        --proto '=https' \
        --proto-redir '=https' \
        --tlsv1.2 \
        --retry 3 \
        --retry-delay 1 \
        --output "$output" \
        "$url"
}

verify_sha256() {
    local expected=$1
    local file=$2

    if ! printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status -; then
        echo "SHA-256 verification failed: $file" >&2
        exit 1
    fi

    echo "Verified: $file"
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

sudo -v

# MakeMKV needs OpenSSL, Expat, Qt5, zlib and libavcodec.
packages=(
    base-devel
    openssl
    expat
    qt5-base
    zlib
    curl
    libfdk-aac
)

# FFmpeg's optimized x86 assembly uses NASM.
if [[ "$(uname -m)" == "x86_64" ]]; then
    packages+=(nasm)
fi
sudo pacman -S --needed "${packages[@]}"

# ---------------------------------------------------------------------------
# Temporary build directory
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
cleanup() {
    rm -rf -- "$TMP"
}
trap cleanup EXIT
cd "$TMP"

# ---------------------------------------------------------------------------
# FFmpeg
# ---------------------------------------------------------------------------

echo "Downloading FFmpeg ${FFMPEG_VERSION}..."

fetch \
    "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    "ffmpeg-${FFMPEG_VERSION}.tar.xz"

verify_sha256 \
    "$FFMPEG_SHA256" \
    "ffmpeg-${FFMPEG_VERSION}.tar.xz"

tar -xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"

echo "Building FFmpeg ${FFMPEG_VERSION}..."

cd "ffmpeg-${FFMPEG_VERSION}"

# Native FFmpeg audio codecs remain enabled, and FDK-AAC is added explicitly.
./configure \
    --prefix="$TMP/ffmpeg" \
    --enable-static \
    --disable-shared \
    --enable-pic \
    --disable-programs \
    --disable-doc \
    --enable-nonfree \
    --enable-libfdk-aac

make -j"$JOBS"
make install

cd "$TMP"

# ---------------------------------------------------------------------------
# MakeMKV
# ---------------------------------------------------------------------------

echo "Downloading MakeMKV ${MAKEMKV_VERSION}..."

fetch \
    "https://www.makemkv.com/download/makemkv-oss-${MAKEMKV_VERSION}.tar.gz" \
    "makemkv-oss-${MAKEMKV_VERSION}.tar.gz"

fetch \
    "https://www.makemkv.com/download/makemkv-bin-${MAKEMKV_VERSION}.tar.gz" \
    "makemkv-bin-${MAKEMKV_VERSION}.tar.gz"

verify_sha256 \
    "$MAKEMKV_OSS_SHA256" \
    "makemkv-oss-${MAKEMKV_VERSION}.tar.gz"

verify_sha256 \
    "$MAKEMKV_BIN_SHA256" \
    "makemkv-bin-${MAKEMKV_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# FFmpeg 9 compatibility patch
# ---------------------------------------------------------------------------

echo "Downloading FFmpeg 9 compatibility patch..."

fetch \
    "$PATCH_URL" \
    "makemkv-ffmpeg9.patch"

verify_sha256 \
    "$PATCH_SHA256" \
    "makemkv-ffmpeg9.patch"

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------

tar -xf "makemkv-oss-${MAKEMKV_VERSION}.tar.gz"
tar -xf "makemkv-bin-${MAKEMKV_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# Build MakeMKV OSS
# ---------------------------------------------------------------------------

echo "Building MakeMKV OSS..."

cd "makemkv-oss-${MAKEMKV_VERSION}"

patch \
    --forward \
    --batch \
    -p1 \
    < "$TMP/makemkv-ffmpeg9.patch"

PKG_CONFIG_PATH="$TMP/ffmpeg/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    ./configure

make -j"$JOBS"
sudo make install

# ---------------------------------------------------------------------------
# Build MakeMKV binary component
# ---------------------------------------------------------------------------

echo "Building MakeMKV binary component..."

cd "$TMP/makemkv-bin-${MAKEMKV_VERSION}"

# MakeMKV may request acceptance of its EULA here.
make -j"$JOBS"
sudo make install

echo
echo "Done."
echo "MakeMKV ${MAKEMKV_VERSION} was installed using FFmpeg ${FFMPEG_VERSION}"
echo "with FDK-AAC support."