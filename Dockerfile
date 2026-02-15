FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    git \
    curl \
    openssh-client \
    coreutils \
    docker-cli \
    jq \
    procps \
    util-linux

COPY golem.sh /opt/golem/golem.sh
COPY process-commands.sh /opt/golem/process-commands.sh
COPY entrypoint.sh /opt/golem/entrypoint.sh
RUN chmod +x /opt/golem/*.sh

ENTRYPOINT ["/opt/golem/entrypoint.sh"]
