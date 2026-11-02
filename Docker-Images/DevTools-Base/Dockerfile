# Base de tooling de desarrollo sin escritorio: Docker Engine, Node + CLIs de IA,
# utilidades de consola. La usan tanto templates headless (DeveloperCLI) como la
# base de escritorio (Desktop-KDE), para que la versión de Node y el set de CLIs
# de IA vivan en un solo sitio.
FROM codercom/example-base:ubuntu-noble

LABEL org.opencontainers.image.title="coder-mks-devtools-base" \
      org.opencontainers.image.description="Docker Engine + Node24/CLIs IA + utilidades de consola, sin escritorio" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-devtools-base:latest"

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        python3 python3-venv python3-pip pipx \
        jq \
        gnupg \
        git-lfs \
        pre-commit \
        dbus \
        cifs-utils \
        nfs-common \
        sshfs \
        fuse3 \
        libfuse2 \
        desktop-file-utils \
        dnsutils \
        net-tools \
        lsof \
        htop \
        ripgrep \
        fzf \
        bat \
        eza \
        tmux \
        direnv \
        yq \
        sqlite3 \
        zip unzip p7zip-full \
        command-not-found \
        bash-completion \
        nano \
        iputils-ping \
        byobu \
    && rm -rf /var/lib/apt/lists/*

# FUSE para permitir AppImages con allow_other (usado por templates de escritorio
# que heredan de esta base; inocuo en headless).
RUN echo "user_allow_other" > /etc/fuse.conf

# Locales
RUN locale-gen es_ES.UTF-8 en_US.UTF-8 && \
    update-locale LANG=es_ES.UTF-8

ENV LANG=es_ES.UTF-8 \
    LC_ALL=es_ES.UTF-8

# Docker Engine y Docker Compose. Siempre instalado: si se arranca dockerd o no
# (DinD) es un coder_parameter del template, no una decisión de imagen.
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (repositorio oficial)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Node.js 24 LTS y el set común de CLIs de IA (igual para todos los templates:
# Developer/Designer/DeveloperAndroid ya no tienen subsets distintos).
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
      | tee /etc/apt/sources.list.d/nodesource.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g --omit=dev --no-update-notifier --no-fund \
        pnpm \
        yarn \
        @openai/codex \
        @anthropic-ai/claude-code \
        @google/gemini-cli \
        @continuedev/cli \
        @qwen-code/qwen-code && \
    npm cache clean --force && \
    rm -rf /var/lib/apt/lists/*

ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/opt/pipx/bin \
    PATH="/opt/pipx/bin:/usr/local/bin:${PATH}"

RUN mkdir -p /opt/pipx /opt/pipx/bin /opt/pipx/venvs && \
    chown -R 1000:1000 /opt/pipx && \
    mkdir -p /home/coder/.local && \
    ln -sfn /opt/pipx/bin /home/coder/.local/bin && \
    chown -R 1000:1000 /home/coder/.local
