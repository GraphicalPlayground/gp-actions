#!/bin/bash
# Copyright (c) - Graphical Playground. All rights reserved.
# For more information, see https://graphical-playground/legal
# mailto:support AT graphical-playground DOT com

source "../../common/common.sh"

set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  gp.fatal "This script is not intended to be sourced. Please run it directly."
fi

gp.dumpContext

if ! gp.isLinux; then
  gp.fatal "This script is only intended to be run on Linux. If you are running this on a different platform, please use the appropriate setup script for your platform."
fi

gp.info "Setting up Linux environment for GitHub Actions..."

if gp.isUbuntu || gp.isDebian; then
  gp.info "Detected Ubuntu/Debian. Installing dependencies using apt-get..."
  gp.startGroup "Updating package lists and installing dependencies..."
  gp.sudo apt-get update
  gp.sudo apt-get install -y clang llvm ninja-build pkg-config \
    libasound2-dev libpulse-dev libaudio-dev libjack-dev libsndio-dev \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
    libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libdrm-dev \
    libgbm-dev libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
    libdbus-1-dev libibus-1.0-dev libudev-dev libwayland-dev libvulkan-dev \
    libwayland-dev wayland-protocols mold
  gp.endGroup
elif gp.isFedora; then
  gp.info "Detected Fedora. Installing dependencies using dnf..."
  gp.startGroup "Updating package lists and installing dependencies..."
  gp.sudo dnf install -y clang llvm ninja-build pkgconf-pkg-config \
    alsa-lib-devel pulseaudio-libs-devel nas-devel jack-audio-connection-kit-devel \
    libX11-devel libXext-devel libXrandr-devel libXcursor-devel libXfixes-devel \
    libXi-devel libXScrnSaver-devel libXtst-devel libxkbcommon-devel libdrm-devel \
    mesa-libgbm-devel mesa-libGL-devel mesa-libGLES-devel mesa-libEGL-devel \
    dbus-devel ibus-devel systemd-devel wayland-devel vulkan-loader-devel \
    wayland-protocols-devel mold
  gp.endGroup
elif gp.isAlpine; then
  gp.info "Detected Alpine. Installing dependencies using apk..."
  gp.startGroup "Updating package lists and installing dependencies..."
  gp.sudo apk add --no-cache clang llvm ninja pkgconfig \
    alsa-lib-dev pulseaudio-dev nas-dev jack-dev \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
    libxi-dev libxsp-dev libxtst-dev libxkbcommon-dev libdrm-dev \
    mesa-dev mesa-gles mesa-egl wayland-protocols mold \
    dbus-dev ibus-dev udev-dev wayland-dev vulkan-loader-dev
  gp.endGroup
elif gp.isArch; then
  gp.info "Detected Arch. Installing dependencies using pacman..."
  gp.startGroup "Updating package lists and installing dependencies..."
  gp.sudo pacman -Syu --noconfirm clang llvm ninja pkgconf \
    alsa-lib libpulse libnas jack2 wayland-protocols mold \
    libx11 libxext libxrandr libxcursor libxfixes \
    libxi libxss libxtst libxkbcommon libdrm \
    mesa libegl-wayland dbus ibus systemd wayland vulkan-headers
  gp.endGroup
else
  gp.fatal "Could not detect Linux distribution. Please ensure you have the necessary dependencies installed for your distribution."
fi

gp.info "Linux environment setup complete. Verifying installations..."

gp.requireCommand clang clang++ ninja cmake mold

gp.info "Clang version: $(clang --version | head -n 1)"
gp.info "Clang++ version: $(clang++ --version | head -n 1)"
gp.info "Ninja version: $(ninja --version)"
gp.info "CMake version: $(cmake --version | head -n 1)"
gp.info "Mold version: $(mold --version | head -n 1)"

gp.info "Enforce clang as the default compiler for C and C++ and mold as the default linker for all build steps."

gp.setEnv "CC" "clang"
gp.setEnv "CXX" "clang++"
gp.setEnv "LDFLAGS" "-fuse-ld=mold"

gp.info "Environment variables set: CC=clang, CXX=clang++, LDFLAGS=-fuse-ld=mold"

gp.info "Linux environment setup and verification complete."
