FROM alpine:3.21
ARG DOVI_TOOL_VERSION=2.1.3
ARG DOVI_TOOL_ARCH=x86_64-unknown-linux-musl

LABEL org.opencontainers.image.description "This image provides a containerized version of the dovi_tool for use with Fileflows to convert Dolby Vision profile 7 to profile 8."

# Add DNS configuration
RUN echo "nameserver 8.8.8.8" > /etc/resolv.conf && \
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf

RUN apk add --no-cache mediainfo jq curl
RUN apk add mkvtoolnix --repository http://dl-3.alpinelinux.org/alpine/edge/main
ADD https://github.com/quietvoid/dovi_tool/releases/download/${DOVI_TOOL_VERSION}/dovi_tool-${DOVI_TOOL_VERSION}-${DOVI_TOOL_ARCH}.tar.gz /tmp
RUN tar -xvf /tmp/dovi_tool-${DOVI_TOOL_VERSION}-${DOVI_TOOL_ARCH}.tar.gz -C /usr/local/bin
RUN mkdir /opt/media

COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY ./dovi_tool.config.json /config/dovi_tool.config.json

RUN rm -rf /tmp/*

WORKDIR /opt/media

ENV TELEGRAM_BOT_TOKEN=""
ENV TELEGRAM_CHAT_ID=""

ENTRYPOINT ["entrypoint.sh"]
