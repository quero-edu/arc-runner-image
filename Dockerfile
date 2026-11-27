ARG RUNNER_VERSION=2.338.2

FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG COMPOSE_VERSION=v5.7.0
ARG COMPOSE_SHA256=7758048ad38e580f22559603312874fec8bb638d021a9e64182385fc17cc12a2

USER root

# Docker Compose CLI plugin. The official image ships the docker CLI and buildx
# but not compose, which ubuntu-latest has and `docker compose` workflows expect.
RUN curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
       "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    && echo "${COMPOSE_SHA256}  /usr/local/lib/docker/cli-plugins/docker-compose" | sha256sum -c - \
    && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose

# Google Chrome stable from Google's apt repository, plus fonts so pages render
# like they do on the GitHub-hosted ubuntu-latest image.
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
       | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       google-chrome-stable \
       fonts-liberation \
       fonts-noto-color-emoji \
       xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# zstd, as on ubuntu-latest. @actions/cache compresses with zstd when the binary
# exists and falls back to gzip otherwise, and the compression method is part of
# the cache version (getCacheVersion in actions/toolkit). Without it, caches saved
# by GitHub-hosted runners never restore here and every job reinstalls from scratch.
RUN apt-get update \
    && apt-get install -y --no-install-recommends zstd \
    && rm -rf /var/lib/apt/lists/*

# C/C++ toolchain (make, gcc, g++), as on ubuntu-latest. Native npm modules without
# prebuilt binaries compile on install: better-sqlite3 13 runs `node-gyp rebuild`
# directly, which fails here with "not found: make".
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

# The base image replaces /etc/sudoers without a secure_path, so `sudo <cmd>`
# fails with "command not found" whenever the caller passes an environment
# without PATH (browser-actions/setup-chrome does this for apt-get).
RUN echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/sudoers \
    && visudo -c

# Chrome's sandbox needs to create user namespaces, which an unprivileged pod
# cannot do ("failed to move to new namespaces"). Tools that honor CHROME_PATH
# (Lighthouse's chrome-launcher, Puppeteer) get a wrapper that adds --no-sandbox.
# google-chrome-stable itself is left untouched.
COPY --chmod=0755 chrome-no-sandbox /usr/local/bin/chrome-no-sandbox
ENV CHROME_PATH=/usr/local/bin/chrome-no-sandbox

USER runner
