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

# Run the gateway with the openclaw user's real HOME (not the inherited /root).
# Skills resolve credential paths via Path.home(); without this they look in
# /root/.openclaw (unreadable by the openclaw user) and report "no access".
exec gosu openclaw env HOME=/home/openclaw node src/server.js
