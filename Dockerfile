# ==========================================
# Stage 1: Build Environment
# ==========================================
FROM alpine:3.23 AS builder

# 1. Pin exact versions and SHAs
ENV MOSQUITTO_VERSION=2.1.2 \
    GPG_KEYS=A0D6EEA1DCAE49A635A3B2F0779B22DFB3E717B7 \
    LWS_VERSION=5.0.0 \
    LWS_SHA256=f853c6582101cfcee3a5a9e28ae92ab19d9735c5f31f0bb2e9794b5106123962 \
    CJSON_VERSION=1.7.19 \
    CJSON_SHA256=7fa616e3046edfa7a28a32d5f9eacfd23f92900fe1f8ccd988c1662f30454562

# Install all build dependencies
RUN set -x && \
    apk --no-cache add \
        build-base \
        cmake \
        gnupg \
        linux-headers \
        openssl-dev \
        util-linux-dev \
        curl \
        libedit-dev \
        libmicrohttpd-dev

# Build libwebsockets (v5.0.0)
RUN wget https://github.com/warmcat/libwebsockets/archive/v${LWS_VERSION}.tar.gz -O /tmp/lws.tar.gz && \
    echo "$LWS_SHA256  /tmp/lws.tar.gz" | sha256sum -c - && \
    mkdir -p /build/lws && \
    tar --strip=1 -xf /tmp/lws.tar.gz -C /build/lws && \
    cd /build/lws && \
    cmake . \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DDISABLE_WERROR=ON \
        -DLWS_IPV6=ON \
        -DLWS_WITHOUT_BUILTIN_GETIFADDRS=ON \
        -DLWS_WITHOUT_CLIENT=ON \
        -DLWS_WITHOUT_EXTENSIONS=ON \
        -DLWS_WITHOUT_TESTAPPS=ON \
        -DLWS_WITH_EXTERNAL_POLL=ON \
        -DLWS_WITH_HTTP2=OFF \
        -DLWS_WITH_SHARED=OFF \
        -DLWS_WITH_ZIP_FOPS=OFF \
        -DLWS_WITH_ZLIB=OFF && \
    make -j "$(nproc)" install

# Build cJSON
RUN wget https://github.com/DaveGamble/cJSON/archive/v${CJSON_VERSION}.tar.gz -O /tmp/cjson.tar.gz && \
    echo "$CJSON_SHA256  /tmp/cjson.tar.gz" | sha256sum -c - && \
    mkdir -p /build/cjson && \
    tar --strip=1 -xf /tmp/cjson.tar.gz -C /build/cjson && \
    cd /build/cjson && \
    cmake . \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DBUILD_SHARED_AND_STATIC_LIBS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DCJSON_BUILD_SHARED_LIBS=OFF \
        -DCJSON_OVERRIDE_BUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr && \
    make -j "$(nproc)" install

# Build Mosquitto and isolate binaries into /out
RUN wget https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz -O /tmp/mosq.tar.gz && \
    wget https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz.asc -O /tmp/mosq.tar.gz.asc && \
    export GNUPGHOME="$(mktemp -d)" && \
    found=''; \
    for server in hkps://keys.openpgp.org hkp://keyserver.ubuntu.com:80 pgp.mit.edu; do \
        gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
    done; \
    test -z "$found" && exit 1; \
    gpg --batch --verify /tmp/mosq.tar.gz.asc /tmp/mosq.tar.gz && \
    mkdir -p /build/mosq && \
    tar --strip=1 -xf /tmp/mosq.tar.gz -C /build/mosq && \
    make -C /build/mosq -j "$(nproc)" \
        CFLAGS="-Wall -O2" \
        WITH_ADNS=no \
        WITH_DOCS=no \
        WITH_SHARED_LIBRARIES=yes \
        WITH_SRV=no \
        WITH_STRIP=yes \
        WITH_TLS_PSK=no \
        WITH_WEBSOCKETS=yes \
        prefix=/usr \
        binary && \
    mkdir -p /out/usr/bin /out/usr/sbin /out/usr/lib && \
    install -s -m755 /build/mosq/client/mosquitto_pub /out/usr/bin/mosquitto_pub && \
    install -s -m755 /build/mosq/client/mosquitto_rr /out/usr/bin/mosquitto_rr && \
    install -s -m755 /build/mosq/client/mosquitto_sub /out/usr/bin/mosquitto_sub && \
    install -s -m644 /build/mosq/lib/libmosquitto.so.1 /out/usr/lib/libmosquitto.so.1 && \
    install -s -m755 /build/mosq/src/mosquitto /out/usr/sbin/mosquitto && \
    install -s -m755 /build/mosq/apps/mosquitto_ctrl/mosquitto_ctrl /out/usr/bin/mosquitto_ctrl && \
    install -s -m755 /build/mosq/apps/mosquitto_passwd/mosquitto_passwd /out/usr/bin/mosquitto_passwd && \
    install -s -m755 /build/mosq/plugins/dynamic-security/mosquitto_dynamic_security.so /out/usr/lib/mosquitto_dynamic_security.so

# ==========================================
# Stage 2: Final Lean Image
# ==========================================
FROM alpine:3.23

# Modern OCI Labels
LABEL org.opencontainers.image.authors="Roger Light <roger@atchoo.org>" \
      org.opencontainers.image.title="Eclipse Mosquitto" \
      org.opencontainers.image.description="Eclipse Mosquitto MQTT Broker with WebSockets (v5.0.0)"

# Install ONLY runtime dependencies
RUN apk --no-cache add ca-certificates tzdata libedit libmicrohttpd && \
    addgroup -S -g 1883 mosquitto 2>/dev/null && \
    adduser -S -u 1883 -D -H -h /var/empty -s /sbin/nologin -G mosquitto -g mosquitto mosquitto 2>/dev/null && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
    chown -R mosquitto:mosquitto /mosquitto

# Copy purely the compiled binaries and libraries from the builder stage
COPY --from=builder /out/usr/bin/ /usr/bin/
COPY --from=builder /out/usr/sbin/ /usr/sbin/
COPY --from=builder /out/usr/lib/ /usr/lib/

# Copy your local configs
COPY entrypoint.sh /
COPY mosquitto.conf /mosquitto/config/mosquitto.conf

RUN chown mosquitto:mosquitto /mosquitto/config/mosquitto.conf && \
    chmod +x /entrypoint.sh

EXPOSE 1883
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]