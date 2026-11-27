# arc-runner-image

Runner image for the self-hosted GitHub Actions runners of the Actions Runner
Controller (ARC) in the `prod-nv` cluster. It extends the official
[`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/blob/main/images/Dockerfile)
with what our workflows expect from `ubuntu-latest` but the official image
leaves out.

Published as `ghcr.io/quero-edu/arc-runner-image`. The scale set that uses it
is defined in `quero-edu/infra-global-k8s`,
`clusters/prod-nv/core/infratools-actions-runner-controller.tf`.

## What it adds

| Addition | Why |
|---|---|
| `google-chrome-stable`, `fonts-liberation`, `fonts-noto-color-emoji` | Lighthouse (`quero-edu/vitality` in `arcadia`) needs a browser. Installing Chrome and its libraries in every job cost about 28 s per job. |
| `CHROME_PATH=/usr/local/bin/chrome-no-sandbox` | Chrome's sandbox needs to create user namespaces, which an unprivileged pod cannot do (`failed to move to new namespaces`). The wrapper adds `--no-sandbox`; `google-chrome-stable` itself is unchanged. Lighthouse's `chrome-launcher` and Puppeteer read `CHROME_PATH`. |
| Docker Compose CLI plugin (`docker compose`), pinned with its SHA-256 | `ubuntu-latest` ships it and workflows that bring up services with `docker compose` (`montilla`) expect it. The official image only has the docker CLI and buildx. It talks to the dind sidecar of the `arc-prod-nv-dind` scale set. |
| `zstd` | `@actions/cache` (used by `setup-node`, `actions/cache` and others) compresses with zstd when it exists and falls back to gzip otherwise, and the compression method is part of the cache version. Without it the caches saved by `ubuntu-latest` never restored here: in `arcadia`, `pnpm install` took 143 s against 32 s on the hosted runner. |
| `build-essential` (`make`, `gcc`, `g++`) | `ubuntu-latest` ships it, and native npm modules without prebuilt binaries compile on install. In `montilla`, `better-sqlite3` 13 runs `node-gyp rebuild` directly and `pnpm install` failed with `not found: make`. |
| `secure_path` in `/etc/sudoers` | The official image replaces `/etc/sudoers` with a single `NOPASSWD` line. Without `secure_path`, `sudo <cmd>` fails with `command not found` when the caller passes an environment without `PATH`, which `browser-actions/setup-chrome` does for `apt-get`. |

The runner still runs as `runner` (uid 1001) with passwordless sudo, as in the
official image.

## Running without the Chrome sandbox

Each runner pod runs one job and is destroyed, and the pages measured are our
own previews and production sites. Running Chrome without its sandbox there is
the usual trade-off for browsers in containers. Do not point this image at
untrusted pages.

## Tags

| Tag | Meaning |
|---|---|
| `<runner version>-<YYYYMMDD>.<run number>` | One per publish run, never reused. Find the build here, then pin its digest. |
| `<runner version>` | Latest build for that runner version. Moves. |
| `latest` | Latest build. Moves. |
| `sha-<commit>` | Latest build of a given commit. Moves on the weekly rebuild. |

**Pin the scale set by digest** (`<tag>@sha256:…`), not by tag. Every tag in
the registry can be pushed again, and a moved tag reaches new nodes without any
change in `infra-global-k8s`. That happened on 2026-11-25: the dated tag was
then only `<runner version>-<YYYYMMDD>`, two merges on the same day published
two builds under `2.338.2-20261125`, and the second one replaced the first.
The run number in the dated tag keeps tags unique from now on, but the digest is
what makes the pin immutable.

The image is rebuilt every Monday to pick up Chrome and Ubuntu security
updates. Pull requests build and smoke-test the image without pushing.

## Updating the runner and Compose versions

Change `ARG RUNNER_VERSION` in the `Dockerfile`. For Compose, change
`COMPOSE_VERSION` and `COMPOSE_SHA256` together, taking the checksum from the
release's `docker-compose-linux-x86_64.sha256` asset. GitHub refuses runners that
fall too far behind the latest release, so keep it current. Then bump the tag
pinned in the scale set in `infra-global-k8s`.
