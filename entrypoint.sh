#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# Persist google-workspace skill credentials across redeploys.
# The skill reads ~/.openclaw/credentials (= /home/openclaw, ephemeral), so point
# that at a directory on the /data volume which survives redeploys.
mkdir -p /data/gws-credentials
chown -R openclaw:openclaw /data/gws-credentials
chmod 700 /data/gws-credentials
install -d -o openclaw -g openclaw /home/openclaw/.openclaw
ln -sfn /data/gws-credentials /home/openclaw/.openclaw/credentials
chown -h openclaw:openclaw /home/openclaw/.openclaw/credentials

# OpenClaw refuses to load plugins whose files are not owned by root
# ("suspicious ownership" guard). Plugins installed into the /data volume are
# owned by the openclaw user (uid 1001) — and the blanket chown above re-owns
# them every boot — so re-own installed plugin packages to root here, or they
# stay blocked and channels like Slack never load.
if [ -d /data/.openclaw/npm/projects ]; then
  chown -R root:root /data/.openclaw/npm/projects
fi

# Git identity + credentials for the senior-SWE agent (marcus) so it can
# clone/commit/push/open PRs. The PAT itself lives in /data/.git-credentials
# (on the volume, mode 600) — NOT in this file. /home/openclaw is ephemeral and
# loses ~/.gitconfig on every redeploy, so re-point git at the volume creds here.
if [ -f /data/.git-credentials ]; then
  chown openclaw:openclaw /data/.git-credentials
  chmod 600 /data/.git-credentials
  gosu openclaw env HOME=/home/openclaw git config --global credential.helper "store --file=/data/.git-credentials"
  gosu openclaw env HOME=/home/openclaw git config --global user.name "Marcus (OpenClaw SWE)"
  gosu openclaw env HOME=/home/openclaw git config --global user.email "marcus@curacel.ai"
  gosu openclaw env HOME=/home/openclaw git config --global --add safe.directory '*'
  gosu openclaw env HOME=/home/openclaw git config --global core.pager cat
  gosu openclaw env HOME=/home/openclaw git config --global init.defaultBranch main
  gosu openclaw env HOME=/home/openclaw git config --global advice.detachedHead false
fi

# Persist the PollyReach skill token across redeploys (Rachael's phone skill).
# The scripts read ~/.config/PollyReach/key.json (= /home/openclaw, ephemeral),
# so keep the token on the /data volume and symlink the dir back on boot.
install -d -o openclaw -g openclaw -m 700 /data/pollyreach
install -d -o openclaw -g openclaw /home/openclaw/.config
ln -sfn /data/pollyreach /home/openclaw/.config/PollyReach
chown -h openclaw:openclaw /home/openclaw/.config/PollyReach

# Run the gateway with the openclaw user's real HOME (not the inherited /root).
# Skills resolve credential paths via Path.home(); without this they look in
# /root/.openclaw (unreadable by the openclaw user) and report "no access".
exec gosu openclaw env HOME=/home/openclaw node src/server.js
