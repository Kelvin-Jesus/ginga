#!/bin/bash
# Android tests and a debug build in a Linux container (JDK 17, Android SDK 36), like CI.
# Needs Docker or OrbStack running. The repository is mounted read-only; Gradle's caches live in
# the `tab2mac-gradle` volume, so later runs are fast.
#
# The image is linux/amd64 even on Apple Silicon: Google ships the Linux SDK tools (AAPT2 from
# Maven, build-tools) for x86_64 only, and an arm64 container fails with "AAPT2 … Daemon startup
# failed". OrbStack and Docker Desktop run it through Rosetta.
#
#   scripts/docker-android.sh              # ./gradlew test assembleDebug
#   scripts/docker-android.sh --info       # extra Gradle arguments are passed through
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo "docker not found (install OrbStack or Docker Desktop)" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker isn't running: start OrbStack or Docker Desktop first" >&2; exit 1; }
docker build --platform linux/amd64 -t tab2mac-android -f docker/android.Dockerfile docker
docker run --rm --platform linux/amd64 \
    -v "$PWD":/src:ro \
    -v tab2mac-gradle:/root/.gradle \
    tab2mac-android "$@"
