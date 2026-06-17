FROM --platform=linux/arm64 debian:bookworm-slim

# Install GraalVM JDK + native-image deps for aarch64
# Use || true to make apt resilient under QEMU emulation (slow downloads sometimes fail)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils \
        build-essential zlib1g-dev musl-tools \
        git \
    && rm -rf /var/lib/apt/lists/* \
    && which curl && curl --version | head -1

# Install GraalVM CE 21 aarch64 (use curl instead of wget for reliability)
ARG GRAAL_VERSION=21.0.2
ARG GRAAL_DIR=graalvm-jdk-${GRAAL_VERSION}+13.1
ARG GRAAL_TARBALL=graalvm-community-jdk-${GRAAL_VERSION}_linux-aarch64_bin.tar.gz
WORKDIR /opt

# Step-by-step with diagnostic prints to identify which step fails
RUN echo "=== STEP 1: which tools ===" \
    && which curl || echo "curl NOT FOUND" \
    && which tar || echo "tar NOT FOUND" \
    && which xz || echo "xz NOT FOUND" \
    && echo "=== STEP 2: download ===" \
    && curl -fL -o ${GRAAL_TARBALL} \
        "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GRAAL_VERSION}/${GRAAL_TARBALL}" || echo "DOWNLOAD FAILED exit=$?" \
    && ls -lh ${GRAAL_TARBALL} || echo "LIST FAILED" \
    && echo "=== STEP 3: extract ===" \
    && tar xzf ${GRAAL_TARBALL} || echo "EXTRACT FAILED" \
    && rm ${GRAAL_TARBALL} \
    && ls /opt/${GRAAL_DIR}/bin/ 2>&1 | head -5 \
    && echo "=== STEP 4: install native-image ===" \
    && /opt/${GRAAL_DIR}/bin/gu install native-image || echo "GU INSTALL FAILED" \
    && echo "=== ALL DONE ==="

ENV JAVA_HOME=/opt/${GRAAL_DIR}
ENV PATH=${JAVA_HOME}/bin:$PATH

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