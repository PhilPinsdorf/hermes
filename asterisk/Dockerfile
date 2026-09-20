# Asterisk 22 LTS, built from source (Debian ships no asterisk package).
#
# Asterisk is only the media layer for Hermes: it registers at the Fritz!Box as
# an IP phone, hands every incoming call to the ARI app "hermes" and dials out
# only when that app tells it to. All call logic lives in the Phoenix app.

ARG DEBIAN_VERSION=trixie-slim

FROM debian:${DEBIAN_VERSION} AS build

ARG ASTERISK_VERSION=22.11.0
ARG ASTERISK_SHA256=3bd5ee040509a3d3cd9b1ba9520c18e6ec0a7e7981ca68c457dcd36ba3c54d94

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl bzip2 patch pkg-config python3 \
    libedit-dev libjansson-dev libxml2-dev libsqlite3-dev uuid-dev libssl-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN curl -fsSLO "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz" \
  && echo "${ASTERISK_SHA256}  asterisk-${ASTERISK_VERSION}.tar.gz" | sha256sum -c - \
  && tar xzf "asterisk-${ASTERISK_VERSION}.tar.gz"

WORKDIR /usr/src/asterisk-${ASTERISK_VERSION}

# BUILD_NATIVE off: the image must run on any x86-64 host, not just the build machine.
# Unneeded modules are not loaded at runtime (etc/modules.conf) rather than
# deselected here: menuselect fails silently on module names it does not know.
RUN ./configure --with-pjproject-bundled --without-dahdi --without-pri --without-ss7 \
  && make menuselect.makeopts \
  && menuselect/menuselect --disable BUILD_NATIVE \
    --enable CORE-SOUNDS-EN-ALAW --disable CORE-SOUNDS-EN-GSM --disable MOH-OPSOUND-WAV \
    menuselect.makeopts

RUN make -j"$(nproc)" \
  && make install DESTDIR=/opt/asterisk \
  && rm -rf /opt/asterisk/usr/include \
  # /var/run is a symlink to /run in Debian; the runtime dir is created below.
  && rm -rf /opt/asterisk/var/run \
  # The line test (HERMES_CALL_MODE=test) plays this file; fail early if sounds are missing.
  && test -f /opt/asterisk/var/lib/asterisk/sounds/en/demo-congrats.alaw

FROM debian:${DEBIAN_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libedit2 libjansson4 libxml2 libsqlite3-0 libuuid1 libssl3t64 \
    gettext-base iproute2 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/asterisk/ /

RUN groupadd --system asterisk \
  && useradd --system --gid asterisk --home-dir /var/lib/asterisk --shell /usr/sbin/nologin asterisk \
  && mkdir -p /etc/asterisk/templates /var/run/asterisk /var/log/asterisk /var/spool/asterisk \
    /var/lib/asterisk/sounds/hermes \
  && chown -R asterisk:asterisk /etc/asterisk /var/run/asterisk /var/log/asterisk \
    /var/spool/asterisk /var/lib/asterisk

COPY --chown=asterisk:asterisk etc/ /etc/asterisk/templates/
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER asterisk

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD asterisk -rx "core show uptime" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
