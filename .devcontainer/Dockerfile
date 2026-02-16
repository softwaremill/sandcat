FROM mcr.microsoft.com/devcontainers/rust:2-1-trixie

# ca-certificates, curl, git already provided by the devcontainers base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gh gosu jq vim \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 scripts/sandcat-init.sh /usr/local/bin/sandcat-init.sh
COPY --chmod=755 scripts/sandcat-user-init.sh /usr/local/bin/sandcat-user-init.sh

USER vscode

# Install Claude Code CLI scoped to the vscode user.
RUN npm install -g @anthropic-ai/claude-code

# Pre-create the Claude config directory and seed onboarding flag so Claude
# Code can use an API key from the environment without interactive setup.
RUN mkdir -p /home/vscode/.claude \
    && echo '{"hasCompletedOnboarding":true}' > /home/vscode/.claude.json

RUN echo 'alias claude-yolo="claude --dangerously-skip-permissions"' >> /home/vscode/.bashrc

USER root
ENTRYPOINT ["/usr/local/bin/sandcat-init.sh"]
