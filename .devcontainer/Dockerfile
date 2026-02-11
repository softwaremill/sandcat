FROM mcr.microsoft.com/devcontainers/rust:2-1-trixie

COPY scripts/sandcat-init.sh /usr/local/bin/sandcat-init.sh
RUN chmod +x /usr/local/bin/sandcat-init.sh

ENTRYPOINT ["/usr/local/bin/sandcat-init.sh"]
