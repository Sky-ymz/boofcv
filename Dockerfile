FROM debian:bookworm-slim

# Install ONLY small host-side tools (no cross gcc via apt — too slow under QEMU).
# The aarch64 cross gcc is pre-staged as a tarball of .deb files in the build
# context (see download_aarch64_debs.sh). Workflow downloads debs on x86_64 host
# (fast native apt) and stages them at /tmp/aarch64-gcc-debs.tar.gz.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils \
        build-essential zlib1g-dev musl-tools file \
        git dpkg \
    && rm -rf /var/lib/apt/lists/* \
    && which curl && curl --version | head -1

# Install pre-staged aarch64 cross gcc + deps from .deb tarball.
# This is the same pattern as GraalVM tarball below — host pre-downloads,
# COPY into container, dpkg -i. Avoids 30+ min QEMU-emulated apt install.
COPY aarch64-gcc-debs.tar.gz /tmp/aarch64-gcc-debs.tar.gz
RUN echo "=== aarch64 cross gcc debs ===" \
    && ls -lh /tmp/aarch64-gcc-debs.tar.gz \
    && mkdir -p /tmp/debs && tar xzf /tmp/aarch64-gcc-debs.tar.gz -C /tmp/debs \
    && ls /tmp/debs/ | head -20 \
    && dpkg -i /tmp/debs/*.deb 2>&1 | tail -20 \
    && which aarch64-linux-gnu-gcc && aarch64-linux-gnu-gcc --version | head -1 \
    && rm -rf /tmp/debs /tmp/aarch64-gcc-debs.tar.gz

# Install GraalVM CE 21 aarch64 — use pre-downloaded tarball from build context
# (downloaded on x86_64 host first, much faster than under QEMU emulation)
# NOTE: tarball extracts to "graalvm-community-openjdk-21.0.2+13.1"
ARG GRAAL_VERSION=21.0.2
ARG GRAAL_DIR=graalvm-community-openjdk-${GRAAL_VERSION}+13.1
WORKDIR /opt

# Pre-staged tarball from build context root (symlinked by workflow step)
COPY graalvm.tar.gz /tmp/graalvm.tar.gz
RUN echo "=== tarball ===" \
    && ls -lh /tmp/graalvm.tar.gz \
    && tar xzf /tmp/graalvm.tar.gz \
    && rm /tmp/graalvm.tar.gz \
    && ls /opt/${GRAAL_DIR}/bin/ | head -5 \
    && echo "=== native-image (pre-installed in lib/svm/bin/) ===" \
    && ls /opt/${GRAAL_DIR}/lib/svm/bin/ \
    && /opt/${GRAAL_DIR}/lib/svm/bin/native-image --version

ENV JAVA_HOME=/opt/${GRAAL_DIR}
ENV PATH=${JAVA_HOME}/bin:${JAVA_HOME}/lib/svm/bin:$PATH
# Symlink so build_aarch64.sh default JAVA_HOME works
RUN ln -sf /opt/${GRAAL_DIR} /opt/graalvm-jdk-${GRAAL_VERSION}+13.1
# Symlink native-image into bin/ so PATH lookup works
RUN ln -sf ${JAVA_HOME}/lib/svm/bin/native-image ${JAVA_HOME}/bin/native-image
# And set HOME so script's $HOME expansion resolves correctly
ENV HOME=/root

WORKDIR /workspace

# Copy build inputs
COPY . /workspace/

# Build the native image
ARG OUTPUT_NAME=boofcv_qr_cli_arm64
ENV OUTPUT_NAME=${OUTPUT_NAME}

RUN chmod +x build_aarch64.sh \
    && ./build_aarch64.sh \
    && ls -lh ${OUTPUT_NAME}

# Default: nothing to run; binary is extracted via `docker buildx build --load`
CMD ["/bin/bash"]