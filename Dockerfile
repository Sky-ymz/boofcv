FROM --platform=linux/arm64 debian:bookworm-slim

# Install GraalVM JDK + native-image deps for aarch64
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget xz-utils \
        build-essential zlib1g-dev musl-tools \
    && rm -rf /var/lib/apt/lists/*

# Install GraalVM CE 21 aarch64
ARG GRAAL_VERSION=21.0.2
ARG GRAAL_DIR=graalvm-jdk-${GRAAL_VERSION}+13.1
ARG GRAAL_TARBALL=graalvm-community-jdk-${GRAAL_VERSION}_linux-aarch64_bin.tar.gz
WORKDIR /opt
RUN wget -q "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GRAAL_VERSION}/${GRAAL_TARBALL}" \
    && tar xzf ${GRAAL_TARBALL} \
    && rm ${GRAAL_TARBALL} \
    && /opt/${GRAAL_DIR}/bin/gu install native-image

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