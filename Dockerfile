FROM ghcr.io/linuxserver/baseimage-alpine:3.21-532ba5e0-ls14

ENV DOCKER_MODS=linuxserver/mods:universal-package-install|linuxserver/mods:universal-cron
ENV INSTALL_PACKAGES=restic|postgresql-client

COPY scripts/backup.sh /etc/periodic/15min

RUN chmod +x /etc/periodic/15min/backup.sh

RUN mkdir -p /data