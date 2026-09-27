# syntax=docker/dockerfile:1
# The Android receiver's checks on Linux, like CI: JDK 17, Android SDK (platform 36,
# build-tools 36.0.0), then `./gradlew test assembleDebug`. Run through scripts/docker-android.sh,
# which mounts the repository read-only at /src (the golden vectors in protocol/ are needed).
# amd64 only: the Linux SDK tools (AAPT2, build-tools) are x86_64 binaries.
FROM --platform=linux/amd64 eclipse-temurin:17-jdk-jammy

# commandlinetools-linux-<build>_latest.zip; any recent build installs the packages below.
ARG CMDLINE_TOOLS_BUILD=11076708
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" -o /tmp/tools.zip \
 && unzip -q /tmp/tools.zip -d "$ANDROID_HOME/cmdline-tools" \
 && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
 && rm /tmp/tools.zip \
 && yes | sdkmanager --licenses >/dev/null \
 && sdkmanager "platforms;android-36" "build-tools;36.0.0" "platform-tools" >/dev/null

# Builds a copy of android/ and protocol/ (never the mounted tree: its build outputs,
# .gradle/ and local.properties belong to the host).
RUN cat > /usr/local/bin/ginga-android-check <<'SCRIPT' && chmod +x /usr/local/bin/ginga-android-check
#!/bin/bash
set -euo pipefail
mkdir -p /work
tar -C /src --exclude='android/.gradle' --exclude='android/.kotlin' --exclude='*/build' --exclude='android/local.properties' \
    -cf - android protocol | tar -C /work -xf -
cd /work/android
./gradlew test assembleDebug --console=plain "$@"
SCRIPT

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/ginga-android-check"]
