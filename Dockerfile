FROM ghcr.io/parkervcp/yolks:debian

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gstreamer-1.0 \
    gir1.2-gst-plugins-base-1.0 \
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
    gstreamer1.0-plugins-base-apps \
    gir1.2-glib-2.0 \
    libgstreamer1.0-dev \
    xvfb \
    chromium \
    curl \
    wget \
    ca-certificates \
    fonts-liberation \
    file \
    tar \
    && rm -rf /var/lib/apt/lists/*


ARG MEDIAMTX_VERSION=1.19.3

RUN wget -O /tmp/mediamtx.tar.gz \
https://github.com/bluenviron/mediamtx/releases/download/v${MEDIAMTX_VERSION}/mediamtx_v${MEDIAMTX_VERSION}_linux_amd64.tar.gz \
&& tar -xzf /tmp/mediamtx.tar.gz -C /tmp \
&& mv /tmp/mediamtx /usr/local/bin/mediamtx \
&& chmod +x /usr/local/bin/mediamtx \
&& rm /tmp/mediamtx.tar.gz


COPY requirements.txt /tmp/requirements.txt

RUN pip3 install --break-system-packages \
    -r /tmp/requirements.txt


COPY entrypoint.sh /home/container/entrypoint.sh

RUN sed -i 's/\r$//' /home/container/entrypoint.sh \
    && chmod +x /home/container/entrypoint.sh \
    && head -5 /home/container/entrypoint.sh \
    && file /home/container/entrypoint.sh


COPY mediamtx.yml /home/container/mediamtx.yml


WORKDIR /home/container

CMD ["/usr/bin/env","bash","/home/container/entrypoint.sh"]
