# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

FROM hashicorp/vault:2.0.1 AS v
FROM mikefarah/yq:4.53.2 AS y
FROM python:3.13

ARG UID=1000
ARG FERN_API_VERSION=5.44.4
ARG NODE_VERSION=22.12.0
ARG GH_VERSION=2.93.0

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && DEBIAN_FRONTEND=noninteractive \
 && apt-get install --no-install-recommends -y \
      git \
      unzip \
      less \
      make \
      rsync \
      openssh-client \
      wget \
      jq \
      curl \
      ca-certificates \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

COPY --from=v /bin/vault /bin/vault
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
COPY --from=y /usr/bin/yq /usr/bin/yq
RUN yq --version

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    tarball="gh_${GH_VERSION}_linux_${arch}.tar.gz"; \
    base="https://github.com/cli/cli/releases/download/v${GH_VERSION}"; \
    curl -fsSL "${base}/${tarball}" -o "/tmp/${tarball}"; \
    curl -fsSL "${base}/gh_${GH_VERSION}_checksums.txt" -o /tmp/gh_checksums.txt; \
    (cd /tmp && grep " ${tarball}$" gh_checksums.txt | sha256sum -c -); \
    tar -xzf "/tmp/${tarball}" -C /tmp; \
    mv "/tmp/gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/${tarball}" /tmp/gh_checksums.txt "/tmp/gh_${GH_VERSION}_linux_${arch}"; \
    gh --version

ENV HOME=/home/nvidia
RUN useradd -u "${UID}" -ms /bin/bash nvidia && chmod 777 "${HOME}"
USER nvidia
ENV PATH="/home/nvidia/.venv/bin:/home/nvidia/.local/node/bin:/home/nvidia/.local/bin:${PATH}"

RUN uv venv /home/nvidia/.venv
RUN --mount=type=bind,source=.,destination=/x,rw uv pip install --python /home/nvidia/.venv/bin/python --requirement /x/requirements.txt

RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz \
 && mkdir -p /home/nvidia/.local/node \
 && tar -xJf /tmp/node.tar.xz -C /home/nvidia/.local/node --strip-components=1 \
 && /home/nvidia/.local/node/bin/npm config set prefix /home/nvidia/.local \
 && /home/nvidia/.local/node/bin/npm install -g "fern-api@${FERN_API_VERSION}" \
 && rm /tmp/node.tar.xz

# Prime ~/.fern/app-preview/ with the docs preview bundle.
RUN --mount=type=bind,source=docs/fern,destination=/x/fern,rw set -eux; \
    cd /x/fern; \
    ( fern docs dev >/tmp/fern-warm.log 2>&1 & echo $! > /tmp/fern-warm.pid ); \
    for i in $(seq 1 60); do \
      if [ -d /home/nvidia/.fern/app-preview/.next ] \
         && [ -f /home/nvidia/.fern/app-preview/etag ]; then \
        break; \
      fi; \
      sleep 2; \
    done; \
    kill "$(cat /tmp/fern-warm.pid)" 2>/dev/null || true; \
    sleep 1; \
    kill -9 "$(cat /tmp/fern-warm.pid)" 2>/dev/null || true; \
    rm -f /tmp/fern-warm.log /tmp/fern-warm.pid; \
    test -d /home/nvidia/.fern/app-preview/.next; \
    test -f /home/nvidia/.fern/app-preview/etag; \
    echo "Primed Fern docs preview bundle:"; \
    ls -la /home/nvidia/.fern/app-preview/
