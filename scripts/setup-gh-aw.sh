#!/usr/bin/env bash
# setup-gh-aw.sh – Install GitHub CLI and the gh-aw (Agentic Workflows) extension.
# Safe to re-run; existing installations are detected and skipped.

set -euo pipefail

# ─── helpers ──────────────────────────────────────────────────────────────────
info()  { echo "ℹ  $*"; }
ok()    { echo "✅ $*"; }
die()   { echo "❌ $*" >&2; exit 1; }

# ─── gh CLI ───────────────────────────────────────────────────────────────────
install_gh_cli() {
  if command -v gh &>/dev/null; then
    ok "gh CLI already installed: $(gh --version | head -1)"
    return
  fi

  info "Installing GitHub CLI …"
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')

  case "$os" in
    linux)
      if command -v apt-get &>/dev/null; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
          | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
          | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -q
        sudo apt-get install -y gh
      elif command -v yum &>/dev/null; then
        sudo dnf install -y 'dnf-command(config-manager)' || true
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
        sudo dnf install -y gh
      else
        die "Unsupported Linux package manager. Install gh manually: https://cli.github.com/"
      fi
      ;;
    darwin)
      if command -v brew &>/dev/null; then
        brew install gh
      else
        die "Homebrew not found. Install gh manually: https://cli.github.com/"
      fi
      ;;
    *)
      die "Unsupported OS: $os. Install gh manually: https://cli.github.com/"
      ;;
  esac

  ok "gh CLI installed: $(gh --version | head -1)"
}

# ─── gh-aw extension ──────────────────────────────────────────────────────────
install_gh_aw() {
  if gh extension list 2>/dev/null | grep -q "gh-aw"; then
    info "gh-aw already installed — upgrading to latest …"
    gh extension upgrade aw 2>/dev/null || true
    ok "gh-aw ready: $(gh aw version 2>/dev/null || echo 'unknown version')"
    return
  fi

  info "Installing gh-aw extension …"
  # Use the canonical install script from the gh-aw repository
  curl -sL https://raw.githubusercontent.com/github/gh-aw/main/install-gh-aw.sh | bash

  ok "gh-aw installed: $(gh aw version 2>/dev/null || echo 'installed')"
}

# ─── verify ───────────────────────────────────────────────────────────────────
verify() {
  info "Verifying installation …"
  gh --version
  gh aw version 2>/dev/null || info "gh aw version command not yet available (may require auth)"
  ok "All tools ready."
}

# ─── main ─────────────────────────────────────────────────────────────────────
main() {
  install_gh_cli
  install_gh_aw
  verify
}

main "$@"
