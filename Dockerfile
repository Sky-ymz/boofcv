FROM debian:bookworm-slim

# Install GraalVM JDK + native-image deps for aarch64
# Use || true to make apt resilient under QEMU emulation (slow downloads sometimes fail)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils \
        build-essential zlib1g-dev musl-tools \
        git \
    && rm -rf /var/lib/apt/lists/* \
    && which curl && curl --version | head -1

# Install GraalVM CE 21 aarch64 — use pre-downloaded tarball from build context
# (downloaded on x86_64 host first, much faster than under QEMU emulation)
# NOTE: tarball extracts to "graalvm-community-openjdk-21.0.2+13.1" (not "graalvm-jdk-...")
ARG GRAAL_VERSION=21.0.2
ARG GRAAL_DIR=graalvm-community-openjdk-${GRAAL_VERSION}+13.1
ARG GRAAL_TARBALL=graalvm-community-jdk-${GRAAL_VERSION}_linux-aarch64_bin.tar.gz
WORKDIR /opt
COPY ${GRAAL_TARBALL} /opt/${GRAAL_TARBALL}
RUN echo "=== GraalVM tarball: ===" \
    && ls -lh /opt/${GRAAL_TARBALL} \
    && file /opt/${GRAAL_TARBALL} \
    && echo "=== extracting ===" \
    && tar xzf /opt/${GRAAL_TARBALL} \
    && rm /opt/${GRAAL_TARBALL} \
    && echo "=== /opt after extract ===" \
    && ls -la /opt/ \
    && ls /opt/${GRAAL_DIR}/bin/ 2>&1 | head -5 \
    && echo "=== gu install native-image ===" \
    && /opt/${GRAAL_DIR}/bin/gu install native-image \
    && /opt/${GRAAL_DIR}/bin/native-image --version

ENV JAVA_HOME=/opt/${GRAAL_DIR}
ENV PATH=${JAVA_HOME}/bin:$PATH
# Convenience symlink so scripts that expect /opt/graalvm-jdk-* still work
RUN ln -sf /opt/${GRAAL_DIR} /opt/graalvm-jdk-${GRAAL_VERSION}+13.1

WORKDIR /workspace

# Copy build inputs
COPY . /workspace/

# Build the native image
ARG OUTPUT_NAME=boofcv_qr_cli_arm64
ENV OUTPUT_NAME=${OUTPUT_NAME}

RUN chmod +x build_aarch64.sh \
    && ./build_aarch64.sh \
    && ls -lh ${OUTPUT_NAME} \
    && file ${OUTPUT_NAME}

# Default: nothing to run; binary is extracted via `docker buildx build --load`
CMD ["/bin/bash"]