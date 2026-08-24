# GitHub CLI uses Firefox in the KasmVNC desktop for `gh auth login --web` (MFA).
export GH_BROWSER=firefox
# Passphrase prompts for SSH keys / SSH commit signing on the XFCE desktop.
if [ -x /usr/bin/ssh-askpass ]; then
  export SSH_ASKPASS=/usr/bin/ssh-askpass
  export SSH_ASKPASS_REQUIRE=prefer
fi
