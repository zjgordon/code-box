# GitHub (SSH, MFA, gh)

Manage public GitHub repositories from the code-box desktop over SSH. GitHub requires 2FA on accounts that contribute code. Git over SSH does not prompt for MFA on each push; MFA is completed in Firefox during `gh auth login --web`, and an Ed25519 key is used for git.

HOME is `/config` (host `./data/config`). Keys and `gh` tokens stay on that volume. They are not baked into the image.

## Tools in the image

| Tool | Role |
|------|------|
| `git`, `openssh-client` | Clone / fetch / push over SSH |
| `gh` | Official GitHub CLI (from [cli.github.com](https://cli.github.com/), not Debian’s older package) |
| `git-lfs` | Large files (`git lfs install --system` already ran at image build) |
| `gh dash` | PR / issue TUI ([dlvhdr/gh-dash](https://github.com/dlvhdr/gh-dash)) |
| `gh markdown-preview` | README preview in Firefox ([yusukebe/gh-markdown-preview](https://github.com/yusukebe/gh-markdown-preview)) |
| `/usr/local/bin/github-mcp` | GitHub MCP for agents (token from `gh auth`; see [mcp.md](mcp.md)) |

GitHub’s SSH host keys are pinned in `/etc/ssh/ssh_known_hosts` (`github.com` and `ssh.github.com`, including port 443). The desktop session starts `ssh-agent` so passphrase-protected keys and SSH commit signing work.

## First-time setup

In a desktop terminal:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cp /workspace/ssh/config.example ~/.ssh/config
chmod 600 ~/.ssh/config
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "code-box"
```

Log in with the browser (completes GitHub MFA / passkey in Firefox):

```bash
gh auth login --hostname github.com --git-protocol ssh --web
```

Upload the same public key as **authentication** and again as **signing** (GitHub treats those as two key types):

```bash
gh ssh-key add ~/.ssh/id_ed25519.pub --title code-box --type authentication
gh ssh-key add ~/.ssh/id_ed25519.pub --title code-box-signing --type signing
```

SSH commit signing (Verified on GitHub). Do this in your user config, not system-wide:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

If port 22 is blocked, use the commented `HostName ssh.github.com` / `Port 443` block in [`data/workspace/ssh/config.example`](../data/workspace/ssh/config.example).

## Everyday commands

```bash
gh repo clone OWNER/REPO /workspace/REPO
gh repo view OWNER/REPO
gh issue list
gh pr list
gh pr create
gh release list
gh dash
gh markdown-preview README.md
```

`gh` uses SSH git remotes after `--git-protocol ssh`. API calls use the token from `gh auth login` (stored under `/config`). The GitHub MCP wrapper (`github-mcp`) uses that same token so agents can list Actions runs, PRs, and issues without a second login. See [mcp.md](mcp.md).

## Checks (do not mutate remotes)

These confirm the toolchain without committing or pushing:

```bash
gh --version
git --version
git lfs version
ssh -V
grep github.com /etc/ssh/ssh_known_hosts
gh auth status
ssh -T git@github.com
gh extension list
gh repo view cli/cli
```

`ssh -T git@github.com` should report successful authentication. `gh repo view` on a public repo checks the API token.

## Files

| Path | Role |
|------|------|
| [`data/workspace/ssh/config.example`](../data/workspace/ssh/config.example) | SSH Host stanzas for GitHub (copy to `~/.ssh/config`) |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `gh: command not found` | Rebuild the image (`docker compose build && docker compose up -d`). |
| Host key verification failed | Image should ship `/etc/ssh/ssh_known_hosts`; confirm `grep github.com /etc/ssh/ssh_known_hosts`. |
| `Permission denied (publickey)` | Key exists, `~/.ssh/config` points at it, key uploaded as **authentication**. `ssh-add -l` after unlocking. |
| `gh auth login` does not open Firefox | `GH_BROWSER=firefox`; default browser is Firefox. Use the printed one-time code if the callback fails. |
| Commits not **Verified** | Upload the key as **signing** as well; `git config --global gpg.format ssh` and `user.signingkey` to the `.pub` file. |
| `gh dash` / `gh markdown-preview` missing | Extensions seed on first desktop start from `/opt/gh-share`. `gh extension list`; if empty, log out of the desktop session and back in. |
| Passphrase prompt never appears | Session `ssh-agent` + `ssh-askpass`. Open a new terminal after the desktop has started. |
| GitHub MCP: needs gh auth | Complete this page first; restart Cursor / Claude / OpenCode. [mcp.md](mcp.md). |
