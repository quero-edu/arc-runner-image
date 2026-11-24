ARG RUNNER_VERSION=2.338.2

FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root

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
