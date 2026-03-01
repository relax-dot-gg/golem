FROM ubuntu:22.04

# Symlink /bin/sh to bash to support bashisms (like pipefail) in docker-compose entrypoints
RUN ln -sf /bin/bash /bin/sh

RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/golem
COPY golem.sh /opt/golem/entrypoint.sh
RUN chmod +x /opt/golem/entrypoint.sh

# Git identity for golem
RUN git config --global user.email "golem@cyberstorm.dev" && \
    git config --global user.name "Golem Executor"

ENTRYPOINT ["bash", "/opt/golem/entrypoint.sh"]
