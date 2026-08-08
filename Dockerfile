# syntax=docker/dockerfile:1
# code-box: KasmVNC desktop with XFCE, Firefox, Cursor IDE, VS Code, and Claude Code CLI
#
# Pin the base image digest after validating a build:
#   docker buildx imagetools inspect ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm
#
# Layer order keeps volatile pins (Cursor, extensions, Claude) late so incremental
# rebuilds reuse apt/Node layers. BuildKit cache mounts speed cold apt/npm installs.

FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

# Keep apt lists in BuildKit cache mounts across builds
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
         > /etc/apt/apt.conf.d/keep-cache

# Mozilla + Microsoft + Docker APT repos (CLI only; engine is the Sysbox sibling)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends gnupg wget ca-certificates \
    && install -d -m 0755 /etc/apt/keyrings \
    && wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
        | gpg --dearmor -o /etc/apt/keyrings/packages.mozilla.org.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list \
    && wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: amd64,arm64,armhf\nSigned-By: /usr/share/keyrings/microsoft.gpg\n' \
        > /etc/apt/sources.list.d/vscode.sources \
    && wget -qO- https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list \
    && printf 'Package: firefox*\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla-firefox

# Desktop + agent tooling (includes VS Code package; extensions installed later)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get remove -y firefox 2>/dev/null || true \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        bat \
        btop \
        build-essential \
        ca-certificates \
        cmake \
        code \
        curl \
        dbus-x11 \
        docker-ce-cli \
        docker-compose-plugin \
        elementary-xfce-icon-theme \
        fd-find \
        firefox \
        fonts-jetbrains-mono \
        fzf \
        git \
        gnupg \
        hicolor-icon-theme \
        jq \
        less \
        libasound2 \
        libdbus-glib-1-2 \
        libgtk-3-0 \
        libpci3 \
        librsvg2-common \
        libssl-dev \
        libxt6 \
        locales \
        nano \
        openssh-client \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        python3-xdg \
        ripgrep \
        rsync \
        sqlite3 \
        thunar \
        thunar-archive-plugin \
        tmux \
        tree \
        unzip \
        wget \
        x11-xserver-utils \
        xarchiver \
        xclip \
        xfce4 \
        xfce4-terminal \
        zip \
    && ln -sf /usr/bin/batcat /usr/bin/bat \
    && ln -sf /usr/bin/fdfind /usr/bin/fd \
    && sed -i '/en_US.UTF-8/s/^# *//' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox 200 \
    && update-alternatives --set x-www-browser /usr/bin/firefox \
    && (update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/bin/firefox 200 2>/dev/null; \
        update-alternatives --set gnome-www-browser /usr/bin/firefox 2>/dev/null; true) \
    && command -v code >/dev/null \
    && command -v docker >/dev/null \
    && test -x /usr/bin/firefox \
        || (echo "ERROR: firefox, code, or docker CLI missing" && exit 1)

# Node via nvm + pinned Claude Code CLI
ARG NODE_VERSION=24
ARG NVM_VERSION=0.40.6
ARG CLAUDE_CODE_VERSION=2.1.220
ENV NVM_DIR=/opt/nvm
RUN --mount=type=cache,target=/root/.npm \
    mkdir -p "$NVM_DIR" \
    && curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
       | NVM_DIR="$NVM_DIR" bash \
    && printf 'export NVM_DIR=/opt/nvm\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"\n' \
       > /etc/profile.d/nvm.sh \
    && chmod +x /etc/profile.d/nvm.sh \
    && echo '. /etc/profile.d/nvm.sh' >> /etc/bash.bashrc \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && ln -sf "$(npm prefix -g)/bin/claude" /usr/local/bin/claude \
    && claude --version

# Curated VS Code extensions (shared dir used by /usr/local/bin/code wrapper)
ENV VSCODE_EXTENSIONS_DIR=/opt/vscode-extensions
RUN mkdir -p "$VSCODE_EXTENSIONS_DIR" /tmp/vscode-user-data \
    && code \
         --install-extension ms-python.python \
         --install-extension dbaeumer.vscode-eslint \
         --install-extension esbenp.prettier-vscode \
         --install-extension eamodio.gitlens \
         --install-extension ms-azuretools.vscode-docker \
         --install-extension redhat.vscode-yaml \
         --install-extension yzhang.markdown-all-in-one \
         --install-extension EditorConfig.EditorConfig \
         --install-extension streetsidesoftware.code-spell-checker \
         --install-extension bradlc.vscode-tailwindcss \
         --install-extension ms-vscode-remote.remote-ssh \
         --extensions-dir "$VSCODE_EXTENSIONS_DIR" \
         --user-data-dir /tmp/vscode-user-data \
         --no-sandbox \
    && code --extensions-dir "$VSCODE_EXTENSIONS_DIR" \
         --user-data-dir /tmp/vscode-user-data \
         --no-sandbox \
         --list-extensions \
    && rm -rf /tmp/vscode-user-data

# Cursor IDE (own layer so CURSOR_VERSION bumps skip apt/Node/extensions)
ARG CURSOR_VERSION=3.14
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    wget -q -L "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/${CURSOR_VERSION}" \
        -O /tmp/cursor.deb \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/cursor.deb \
    && rm -f /tmp/cursor.deb \
    && if [ ! -x /usr/bin/cursor ]; then \
         CURSOR_BIN=$(dpkg -L cursor 2>/dev/null | grep -E '/bin/cursor$|/cursor$' | head -1); \
         if [ -n "$CURSOR_BIN" ] && [ -x "$CURSOR_BIN" ]; then ln -sf "$CURSOR_BIN" /usr/bin/cursor; fi; \
       fi \
    && test -x /usr/bin/cursor || (echo "ERROR: cursor missing" && exit 1)

RUN mkdir -p /etc/firefox/policies
COPY firefox-policies.json /etc/firefox/policies/policies.json

# Upstream kclient removed pcm-player.js but still references it in index.html
# (linuxserver/kclient#8). Stub the file so nosniff does not treat the HTML
# 404 as a blocked script MIME mismatch.
RUN printf '// removed upstream; stub for legacy kclient index.html reference\n' \
      > /kclient/public/js/pcm-player.js

COPY root/ /

RUN chmod +x /defaults/startwm.sh /usr/local/bin/code
