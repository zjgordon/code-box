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

# Mozilla + Microsoft + Docker + GitHub CLI APT repos (Docker CLI only; engine is the Sysbox sibling)
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
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && printf 'Package: firefox*\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla-firefox \
    && printf 'Package: gh\nPin: origin cli.github.com\nPin-Priority: 1001\n' \
        > /etc/apt/preferences.d/github-cli

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
        gh \
        git \
        git-lfs \
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
        ssh-askpass \
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
    && command -v gh >/dev/null \
    && command -v git-lfs >/dev/null \
    && test -x /usr/bin/firefox \
        || (echo "ERROR: firefox, code, docker CLI, gh, or git-lfs missing" && exit 1) \
    && git lfs install --system \
    && printf '%s\n' \
        '# GitHub SSH host keys: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints' \
        'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
        'github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=' \
        'github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=' \
        'ssh.github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
        'ssh.github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=' \
        'ssh.github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=' \
        '[ssh.github.com]:443 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
        '[ssh.github.com]:443 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=' \
        '[ssh.github.com]:443 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=' \
        > /etc/ssh/ssh_known_hosts \
    && grep -q 'github.com ssh-ed25519' /etc/ssh/ssh_known_hosts \
    && grep -q 'ssh.github.com ssh-ed25519' /etc/ssh/ssh_known_hosts

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

# OpenCode CLI (own layer so OPENCODE_VERSION bumps skip earlier layers)
ARG OPENCODE_VERSION=1.18.18
RUN --mount=type=cache,target=/root/.npm \
    . "$NVM_DIR/nvm.sh" \
    && npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && ln -sf "$(npm prefix -g)/bin/opencode" /usr/local/bin/opencode \
    && opencode --version

# GitHub CLI extensions (own layer so extension bumps skip earlier layers)
# Seeded into $HOME on first desktop start; see /defaults/startwm.sh
RUN mkdir -p /opt/gh-home /opt/gh-share \
    && HOME=/opt/gh-home XDG_DATA_HOME=/opt/gh-share \
         gh extension install dlvhdr/gh-dash \
    && HOME=/opt/gh-home XDG_DATA_HOME=/opt/gh-share \
         gh extension install yusukebe/gh-markdown-preview \
    && test -d /opt/gh-share/gh/extensions/gh-dash \
    && test -d /opt/gh-share/gh/extensions/gh-markdown-preview \
    && ls -la /opt/gh-share/gh/extensions

# Playwright MCP + Chromium (own layer so PLAYWRIGHT_MCP_VERSION bumps skip earlier layers)
# Shared by Cursor, Claude Code, and OpenCode via /usr/local/bin/playwright-mcp
ARG PLAYWRIGHT_MCP_VERSION=0.0.79
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.npm \
    . "$NVM_DIR/nvm.sh" \
    && npm install -g "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
    && MCP_DIR="$(npm prefix -g)/lib/node_modules/@playwright/mcp" \
    && PW_CLI="$(find "$MCP_DIR" -path '*/playwright-core/cli.js' | head -1)" \
    && test -n "$PW_CLI" -a -f "$PW_CLI" \
    && export DEBIAN_FRONTEND=noninteractive \
    && mkdir -p "$PLAYWRIGHT_BROWSERS_PATH" \
    && node "$PW_CLI" install-deps chromium \
    && node "$PW_CLI" install chromium \
    && chmod -R a+rX "$PLAYWRIGHT_BROWSERS_PATH" \
    && test -x "$(npm prefix -g)/bin/playwright-mcp" \
    && test -d "$PLAYWRIGHT_BROWSERS_PATH" \
    && ls "$PLAYWRIGHT_BROWSERS_PATH"

RUN mkdir -p /etc/firefox/policies
COPY firefox-policies.json /etc/firefox/policies/policies.json

# Upstream kclient removed pcm-player.js but still references it in index.html
# (linuxserver/kclient#8). Stub the file so nosniff does not treat the HTML
# 404 as a blocked script MIME mismatch.
RUN printf '// removed upstream; stub for legacy kclient index.html reference\n' \
      > /kclient/public/js/pcm-player.js

COPY root/ /

RUN chmod +x /defaults/startwm.sh /usr/local/bin/code /usr/local/bin/playwright-mcp \
    && echo '[ -f /etc/profile.d/github.sh ] && . /etc/profile.d/github.sh' >> /etc/bash.bashrc
