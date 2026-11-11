# ==========================================
# Stage 1: Build Environment
# ==========================================
FROM alpine:3.23 AS builder

# Use supplied build arguments, or these defaults when omitted
ARG MOSQUITTO_VERSION=2.1.2
ARG LWS_VERSION=5.0.0
ARG CJSON_VERSION=1.7.19

# Install all build dependencies
RUN set -eux; \
    apk --no-cache add \
        build-base \
        cmake \
        linux-headers \
        openssl-dev \
        util-linux-dev \
        curl \
        ca-certificates \
        libedit-dev \
        libmicrohttpd-dev

# Build libwebsockets from GitHub
RUN set -eu; \
    curl --fail --show-error --location \
        --retry 5 --retry-all-errors --retry-delay 2 \
        --connect-timeout 20 --max-time 180 \
        --output /tmp/lws.tar.gz \
        "https://github.com/warmcat/libwebsockets/archive/refs/tags/v${LWS_VERSION}.tar.gz"; \
    mkdir -p /build/lws; \
    tar --strip=1 -xf /tmp/lws.tar.gz -C /build/lws; \
    cd /build/lws; \
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
        -DLWS_WITH_ZLIB=OFF; \
    make -j "$(nproc)" install

# Build cJSON from GitHub
RUN set -eu; \
    curl --fail --show-error --location \
        --retry 5 --retry-all-errors --retry-delay 2 \
        --connect-timeout 20 --max-time 180 \
        --output /tmp/cjson.tar.gz \
        "https://github.com/DaveGamble/cJSON/archive/refs/tags/v${CJSON_VERSION}.tar.gz"; \
    mkdir -p /build/cjson; \
    tar --strip=1 -xf /tmp/cjson.tar.gz -C /build/cjson; \
    cd /build/cjson; \
    cmake . \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DBUILD_SHARED_AND_STATIC_LIBS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DCJSON_BUILD_SHARED_LIBS=OFF \
        -DCJSON_OVERRIDE_BUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr; \
    make -j "$(nproc)" install

# Build Mosquitto from GitHub and isolate binaries into /out
RUN set -eu; \
    curl --fail --show-error --location \
        --retry 5 --retry-all-errors --retry-delay 2 \
        --connect-timeout 20 --max-time 180 \
        --output /tmp/mosq.tar.gz \
        "https://github.com/eclipse-mosquitto/mosquitto/archive/refs/tags/v${MOSQUITTO_VERSION}.tar.gz"; \
    mkdir -p /build/mosq; \
    tar --strip=1 -xf /tmp/mosq.tar.gz -C /build/mosq; \
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
        binary; \
    mkdir -p /out/usr/bin /out/usr/sbin /out/usr/lib; \
    install -s -m755 /build/mosq/client/mosquitto_pub /out/usr/bin/mosquitto_pub; \
    install -s -m755 /build/mosq/client/mosquitto_rr /out/usr/bin/mosquitto_rr; \
    install -s -m755 /build/mosq/client/mosquitto_sub /out/usr/bin/mosquitto_sub; \
    install -s -m644 /build/mosq/lib/libmosquitto.so.1 /out/usr/lib/libmosquitto.so.1; \
    install -s -m755 /build/mosq/src/mosquitto /out/usr/sbin/mosquitto; \
    install -s -m755 /build/mosq/apps/mosquitto_ctrl/mosquitto_ctrl /out/usr/bin/mosquitto_ctrl; \
    install -s -m755 /build/mosq/apps/mosquitto_passwd/mosquitto_passwd /out/usr/bin/mosquitto_passwd; \
    install -s -m755 /build/mosq/plugins/dynamic-security/mosquitto_dynamic_security.so /out/usr/lib/mosquitto_dynamic_security.so

# ==========================================
# Stage 2: Final Lean Image
# ==========================================
FROM alpine:3.23

LABEL org.opencontainers.image.authors="Roger Light <roger@atchoo.org>" \
      org.opencontainers.image.title="Eclipse Mosquitto" \
      org.opencontainers.image.description="Eclipse Mosquitto MQTT Broker with WebSockets"

# Install runtime dependencies and create the Mosquitto user
RUN set -eux; \
    apk --no-cache add \
        ca-certificates \
        tzdata \
        libedit \
        libmicrohttpd; \
    addgroup -S -g 1883 mosquitto; \
    adduser -S -u 1883 -D -H \
        -h /var/empty \
        -s /sbin/nologin \
        -G mosquitto \
        -g mosquitto \
        mosquitto; \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log; \
    chown -R mosquitto:mosquitto /mosquitto

# Copy compiled binaries and libraries
COPY --from=builder /out/usr/bin/ /usr/bin/
COPY --from=builder /out/usr/sbin/ /usr/sbin/
COPY --from=builder /out/usr/lib/ /usr/lib/

# Copy local entrypoint and configuration
COPY entrypoint.sh /entrypoint.sh
COPY mosquitto.conf /mosquitto/config/mosquitto.conf

RUN chown mosquitto:mosquitto /mosquitto/config/mosquitto.conf && \
    chmod +x /entrypoint.sh

EXPOSE 1883

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]