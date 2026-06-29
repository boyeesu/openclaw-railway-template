FROM node:24-bookworm

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 \
    python3.11-venv \
    python3-pip \
    tini \
    build-essential \
    jq \
    bc \
    zip \
    unzip \
  && rm -rf /var/lib/apt/lists/*

# The google-workspace skill (Rachael/Ailen) documents every command as bare
# `python3 scripts/google_tools.py ...` (SKILL.md + references/commands.md), so
# the agent invokes the SYSTEM python3 — not the skill's venv. Install the Google
# client libs into the system interpreter so those documented commands work.
# Baked here (not via entrypoint/PYTHONPATH) so it survives redeploys AND clawhub
# skill reinstalls, which would overwrite any in-skill doc/path patch.
# --break-system-packages: Debian's python3 is externally-managed; nothing
# Google-related exists in system site-packages, so there's no conflict.
RUN python3 -m pip install --break-system-packages --no-cache-dir \
    google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2

RUN npm install -g openclaw@2026.6.10
RUN npm install -g clawhub@latest
# Railway CLI so the SWE agent (marcus) can pull deploy/build logs and run
# service-level recovery (redeploy/restart) against the project it runs in.
# Auth is non-interactive via the RAILWAY_TOKEN project-token env var (set as a
# Railway variable — NOT baked into the image).
RUN npm install -g @railway/cli@latest
# Buffer CLI so the content agent (Rachael) can schedule social posts reliably.
# Auth is non-interactive via the BUFFER_API_KEY env var (set as a Railway
# variable — NOT baked into the image). Usage is documented in the `buffer`
# skill at /data/workspace/skills/buffer/SKILL.md.
RUN npm install -g @bufferapp/cli@latest

# Renderer for the excalidraw-diagram skill (agents ailen + marcus): a Python
# venv with Playwright + headless Chromium so the skill can render .excalidraw
# JSON → PNG and run its visual validate loop. Chromium + its system libs are
# baked into the image (Railway wipes runtime changes to / on redeploy; only
# /data persists). PLAYWRIGHT_BROWSERS_PATH must be set here AND at runtime so
# Playwright finds the baked browser; the skill's SKILL.md is patched to call
# /opt/render-venv/bin/python directly (it does not use `uv`).
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN python3 -m venv /opt/render-venv \
  && /opt/render-venv/bin/pip install --no-cache-dir playwright \
  && /opt/render-venv/bin/playwright install --with-deps chromium \
  && chmod -R a+rX /opt/render-venv /opt/pw-browsers

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app \
  && mkdir -p /data && chown openclaw:openclaw /data \
  && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
