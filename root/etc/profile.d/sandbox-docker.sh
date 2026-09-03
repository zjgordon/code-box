# Sibling DinD: the Docker CLI talks to sandbox-dind, not this container.
# npm 11 does not accept npm_config_devdir (Cursor sandbox cache).
unset npm_config_devdir 2>/dev/null || true

# Interactive shells only — do not pollute scp, bash -c, or agent stdout.
# Guard: /etc/profile and bash.bashrc may both source this file.
case $- in
  *i*)
    if [ -n "${DOCKER_HOST:-}" ] && [ -z "${CODE_BOX_SANDBOX_HINT:-}" ]; then
      export CODE_BOX_SANDBOX_HINT=1
      echo "Docker: sibling DinD. Published ports: http://sandbox-dind:<port> (not 127.0.0.1)"
      if command -v docker >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        if ! timeout 2 docker info >/dev/null 2>&1; then
          echo "sandbox-dind not ready; wait and retry: docker info" >&2
        fi
      fi
    fi
    ;;
esac
