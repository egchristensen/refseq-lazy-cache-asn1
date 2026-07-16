# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04 AS builder

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG NCBI_CXX_TOOLKIT_REPO=https://github.com/ncbi/ncbi-cxx-toolkit-public.git
ARG NCBI_CXX_TOOLKIT_REF=fe8144adf21fc19db6b9c8c96aa623965419e8bd
ARG GCC_MAJOR=12
ARG NCBI_BUILD_JOBS=8

RUN test "$TARGETARCH" = arm64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential gcc-${GCC_MAJOR} g++-${GCC_MAJOR} \
    cmake ninja-build pkg-config ccache python3 \
    zlib1g-dev libbz2-dev liblzma-dev libzstd-dev libssl-dev \
    libxml2-dev libxslt1-dev libexpat1-dev \
    libcurl4-openssl-dev libsqlite3-dev libpcre3-dev \
    libdb-dev \
    libgd-dev libfreetype6-dev libpng-dev libjpeg-dev libtiff-dev libgeos-dev \
    ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

ENV CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
RUN uname -m \
 && test "$(dpkg --print-architecture)" = arm64 \
 && gcc-12 --version \
 && g++-12 --version \
 && cmake --version

RUN mkdir -p /scratch/src /scratch/build /opt/ncbi /payload
COPY src/gks_ncbi_sequence_probe.cpp /payload/
COPY docker/CMakeLists.gks_ncbi_sequence_probe.app.txt /payload/
COPY docker/patch_toolkit_tree.sh /usr/local/bin/

RUN git clone --filter=blob:none "$NCBI_CXX_TOOLKIT_REPO" /scratch/src/ncbi-cxx \
 && git -C /scratch/src/ncbi-cxx fetch --depth=1 origin "$NCBI_CXX_TOOLKIT_REF" \
 && git -C /scratch/src/ncbi-cxx checkout --detach "$NCBI_CXX_TOOLKIT_REF" \
 && test "$(git -C /scratch/src/ncbi-cxx rev-parse HEAD)" = "$NCBI_CXX_TOOLKIT_REF" \
 && git -C /scratch/src/ncbi-cxx rev-parse HEAD \
 && /usr/local/bin/patch_toolkit_tree.sh /scratch/src/ncbi-cxx /payload

RUN cmake -S /scratch/src/ncbi-cxx/src -B /scratch/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/ncbi \
      -DCMAKE_C_COMPILER=/usr/bin/gcc-12 \
      -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 \
      -DCMAKE_CXX_STANDARD=20 \
      -DCMAKE_CXX_STANDARD_REQUIRED=ON \
      -DCMAKE_CXX_EXTENSIONS=OFF \
      -DBUILD_SHARED_LIBS=ON \
      -DNCBI_PTBCFG_SKIP_ANALYSIS=ON \
      -DNCBI_PTBCFG_ADDTEST=OFF \
      -DNCBI_PTBCFG_ADDCHECK=OFF \
 && cmake --build /scratch/build --parallel "$NCBI_BUILD_JOBS" --target \
      prime_cache asn_cache_test gks_ncbi_sequence_probe \
      asnvalidate asn2asn asn2fasta asn2flat asn_cleanup annotwriter \
 && mkdir -p /opt/ncbi/bin /opt/ncbi/lib \
 && cp -a /scratch/build/bin/. /opt/ncbi/bin/ \
 && cp -a /scratch/build/lib/. /opt/ncbi/lib/

FROM ubuntu:22.04 AS bcftools-builder
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG HTSLIB_REF=1.20
ARG BCFTOOLS_REF=1.20
RUN test "$TARGETARCH" = arm64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential autoconf automake pkg-config git ca-certificates \
    zlib1g-dev libbz2-dev liblzma-dev libcurl4-openssl-dev libssl-dev \
 && rm -rf /var/lib/apt/lists/* \
 && git clone --branch "$HTSLIB_REF" --depth=1 --recurse-submodules --shallow-submodules \
      https://github.com/samtools/htslib.git /src/htslib \
 && git clone --branch "$BCFTOOLS_REF" --depth=1 https://github.com/samtools/bcftools.git /src/bcftools \
 && make -C /src/htslib -j4 \
 && make -C /src/htslib install prefix=/opt/hts \
 && make -C /src/bcftools -j4 HTSDIR=/src/htslib \
 && make -C /src/bcftools install prefix=/opt/hts \
 && /opt/hts/bin/bcftools --version \
 && /opt/hts/bin/tabix --version

FROM ubuntu:22.04 AS runtime
ARG TARGETARCH
ARG NCBI_CXX_TOOLKIT_REF=fe8144adf21fc19db6b9c8c96aa623965419e8bd
ARG GCC_MAJOR=12
ARG DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.source="https://github.com/egchristensen/ncbi_cxx_toolkit_installation_docker" \
      org.opencontainers.image.revision="$NCBI_CXX_TOOLKIT_REF" \
      org.opencontainers.image.description="NCBI-native GKS sequence cache experiment" \
      io.gks.targetarch="$TARGETARCH" \
      io.gks.compiler="gcc-$GCC_MAJOR C++20"

RUN test "$TARGETARCH" = arm64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    libzstd1 zlib1g libbz2-1.0 liblzma5 libssl3 libdb5.3 \
    libxml2 libxslt1.1 libexpat1 libcurl4 libsqlite3-0 libpcre3 \
    libgd3 libfreetype6 libpng16-16 libjpeg-turbo8 libtiff5 libgeos3.10.2 \
    bcftools tabix time strace python3 ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/ncbi /opt/ncbi
COPY --from=bcftools-builder /opt/hts /opt/hts
ENV PATH="/opt/ncbi/bin:/opt/hts/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/ncbi/lib:/opt/hts/lib"
WORKDIR /data
RUN prime_cache -h >/dev/null \
 && asn_cache_test -h >/dev/null \
 && gks_ncbi_sequence_probe -help >/dev/null \
 && bcftools --version >/dev/null
CMD ["/bin/bash"]
