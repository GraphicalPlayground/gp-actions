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

if ! gp.iswindows; then
  gp.fatal "This script is only intended to be run on Windows. If you are running this on a different platform, please use the appropriate setup script for your platform."
fi

gp.info "Setting up Windows environment for GitHub Actions..."

gp.startGroup "Installing dependencies using Chocolatey..."
gp.sudo choco install -y ninja cmake mold llvm
gp.endGroup

gp.info "Windows environment setup complete. Verifying installations..."

gp.requireCommand clang-cl ninja cmake mold

gp.info "Clang version: $(clang-cl --version | head -n 1)"
gp.info "Ninja version: $(ninja --version)"
gp.info "CMake version: $(cmake --version | head -n 1)"
gp.info "Mold version: $(mold --version | head -n 1)"

gp.info "Enforce clang-cl as the default compiler for C and C++ and mold as the default linker for all build steps."

gp.setEnv "CC" "clang-cl"
gp.setEnv "CXX" "clang-cl"
gp.setEnv "LDFLAGS" "-fuse-ld=mold"

gp.info "Environment variables set: CC=clang-cl, CXX=clang-cl, LDFLAGS=-fuse-ld=mold"

gp.info "Windows environment setup and verification complete."
