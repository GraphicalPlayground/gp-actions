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

if ! gp.isMacOS; then
  gp.fatal "This script is only intended to be run on MacOS. If you are running this on a different platform, please use the appropriate setup script for your platform."
fi

gp.info "Setting up MacOS environment for GitHub Actions..."

gp.info "No need to install Clang, as it is included with Xcode Command Line Tools."

gp.startGroup "Installing dependencies using Homebrew..."
gp.sudo brew update
gp.sudo brew install ninja cmake mold
gp.endGroup

gp.info "MacOS environment setup complete. Verifying installations..."

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

gp.info "MacOS environment setup and verification complete."
