FROM ghcr.io/parkervcp/yolks:debian

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1


# ============================================================
# Versiones fijadas
# ============================================================
#
# SRTLA_COMMIT: revisión confirmada en tu servidor actual.
#
# BELABOX_SRT_COMMIT: sustitúyelo por el hash que quieras
# fijar. Obtén el HEAD actual con:
#
#   git ls-remote https://github.com/BELABOX/srt.git HEAD
#
# ============================================================

ARG MEDIAMTX_VERSION=1.19.3
ARG BELABOX_SRT_REPOSITORY=https://github.com/BELABOX/srt.git
ARG BELABOX_SRT_COMMIT=4b6e11be7d2090a3c982c71903b56ed748075e9a
ARG SRTLA_REPOSITORY=https://github.com/BELABOX/srtla.git
ARG SRTLA_COMMIT=37862da3d0c13b46956efd3f88877053293d97d6

# ============================================================
# 1. DEPENDENCIAS DEL SISTEMA
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gstreamer-1.0 \
    gir1.2-gst-plugins-base-1.0 \
    gir1.2-glib-2.0 \
    ffmpeg \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-rtsp \
    gstreamer1.0-x \
    gstreamer1.0-gl \
    gstreamer1.0-plugins-base-apps \
    gstreamer1.0-nice \
    libgstreamer1.0-dev \
    xvfb \
    chromium \
    curl \
    wget \
    ca-certificates \
    fonts-liberation \
    file \
    tar \
    git \
    build-essential \
    cmake \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 2. MEDIAMTX
# ============================================================

RUN set -eux; \
    wget -O /tmp/mediamtx.tar.gz \
      "https://github.com/bluenviron/mediamtx/releases/download/v${MEDIAMTX_VERSION}/mediamtx_v${MEDIAMTX_VERSION}_linux_amd64.tar.gz"; \
    tar -xzf /tmp/mediamtx.tar.gz -C /tmp; \
    install -m 0755 /tmp/mediamtx /usr/local/bin/mediamtx; \
    rm -f /tmp/mediamtx.tar.gz /tmp/mediamtx

# ============================================================
# 3. BELABOX PATCHED SRT
#
# Debe compilarse ANTES de srtla_rec.
# Instala la biblioteca SRT modificada de BELABOX y
# srt-live-transmit, que actuará como receptor SRT intermedio.
# ============================================================

RUN set -eux; \
    git clone "${BELABOX_SRT_REPOSITORY}" /tmp/belabox-srt; \
    cd /tmp/belabox-srt; \
    git checkout "${BELABOX_SRT_COMMIT}"; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DENABLE_SHARED=ON \
      -DENABLE_STATIC=OFF \
      -DENABLE_APPS=ON; \
    make -j"$(nproc)"; \
    make install; \
    ldconfig; \
    test -x /usr/local/bin/srt-live-transmit; \
    rm -rf /tmp/belabox-srt

# ============================================================
# 4. SRTLA RECEIVER
#
# Se compila después del SRT de BELABOX para que srtla_rec
# se enlace contra la biblioteca SRT modificada.
# ============================================================

RUN set -eux; \
    git clone "${SRTLA_REPOSITORY}" /tmp/srtla; \
    cd /tmp/srtla; \
    git checkout "${SRTLA_COMMIT}"; \
    make; \
    test -x ./srtla_rec; \
    install -m 0755 ./srtla_rec /usr/local/bin/srtla_rec; \
    /usr/local/bin/srtla_rec -v; \
    rm -rf /tmp/srtla

# ============================================================
# 5. PYTHON
# ============================================================

COPY requirements.txt /tmp/requirements.txt

RUN python3 -m pip install \
    --break-system-packages \
    --no-cache-dir \
    -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

# ============================================================
# 6. ARCHIVOS DE CONFIGURACIÓN
# ============================================================

WORKDIR /home/container

COPY entrypoint.sh /home/container/entrypoint.sh
COPY mediamtx.yml /home/container/mediamtx.yml

RUN sed -i 's/\r$//' /home/container/entrypoint.sh \
    && chmod 0755 /home/container/entrypoint.sh \
    && mkdir -p \
       /home/container/logs \
       /home/container/fallback \
       /home/container/scripts

# ============================================================
# 7. VERIFICACIÓN DE DEPENDENCIAS
# ============================================================

RUN set -eux; \
    command -v python3; \
    command -v ffmpeg; \
    command -v ffprobe; \
    command -v curl; \
    command -v mediamtx; \
    command -v srtla_rec; \
    command -v srt-live-transmit; \
    python3 --version; \
    ffmpeg -hide_banner -version | head -n 1; \
    mediamtx --version; \
    srtla_rec -v; \
    srt-live-transmit -version 2>&1 | head -n 5 || true

# ============================================================
# 8. ARRANQUE
# ============================================================

CMD ["/usr/bin/env", "bash", "/home/container/entrypoint.sh"]
