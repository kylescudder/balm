#!/usr/bin/env bash
# Balm - first-run setup
#
# Mirrors the Deadwax Club and Diald Club setup shape:
#   1. Check required CLI tools
#   2. Create local native-app and BFF configuration
#   3. Install JavaScript dependencies
#   4. Generate the Xcode project
#   5. Offer sanity tests/builds

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
step() { printf "\n${BLUE}${BOLD}==>${NC} ${BOLD}%s${NC}\n" "$1"; }
ok()   { printf "${GREEN}ok${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "${RED}x${NC} %s\n" "$1"; }
note() { printf "${DIM}  %s${NC}\n" "$1"; }

is_mac() { [[ "${OSTYPE:-}" == darwin* ]]; }

if ! is_mac; then
  warn "This script is designed for macOS. Web and BFF setup will run; Xcode steps will be skipped."
fi

step "Checking required tools"
MISSING_TOOLS=()
need() {
  local cmd="$1"
  local hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd present"
  else
    err "$cmd not found - $hint"
    MISSING_TOOLS+=("$cmd")
  fi
}

need bun "install from https://bun.sh or run: brew install oven-sh/bun/bun"

if is_mac; then
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew is required on macOS - install from https://brew.sh"
    MISSING_TOOLS+=("brew")
  fi
  need xcodegen "brew install xcodegen"
fi

if command -v netlify >/dev/null 2>&1; then
  ok "netlify CLI present (optional)"
else
  note "netlify CLI not installed (optional). Use 'bunx netlify' or install netlify-cli."
fi

if (( ${#MISSING_TOOLS[@]} > 0 )); then
  err "Install the missing tools above and re-run setup.sh."
  exit 1
fi

step "Local configuration"

if [[ ! -f Config/Secrets.xcconfig ]]; then
  cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
  ok "Created Config/Secrets.xcconfig from the example"
else
  ok "Config/Secrets.xcconfig already exists"
fi

if [[ ! -f Server/.env.local ]]; then
  cp Server/.env.example Server/.env.local
  warn "Created Server/.env.local from the example - add the Atlassian client secret before running the BFF."
else
  ok "Server/.env.local already exists"
fi

if grep -Eq '^ATLASSIAN_CLIENT_(ID|SECRET)=$' Server/.env.local 2>/dev/null; then
  warn "Server/.env.local still has empty Atlassian credentials."
fi

step "Install JavaScript dependencies"
bun install --cwd Site --frozen-lockfile
ok "Site dependencies installed"
bun install --cwd Server --no-save
ok "BFF dependencies installed"

if is_mac; then
  step "Generate Xcode project"
  if [[ -d Balm.xcodeproj ]]; then
    rm -rf Balm.xcodeproj
  fi
  xcodegen generate
  ok "Generated Balm.xcodeproj"

  if command -v xcodebuild >/dev/null 2>&1; then
    read -p "Run Swift package tests and a simulator build now? Takes a few minutes. [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      swift test --package-path Balm/BalmCore
      ok "BalmCore tests succeeded"
      xcodebuild build \
        -project Balm.xcodeproj \
        -scheme Balm \
        -configuration Debug \
        -destination 'generic/platform=iOS Simulator' \
        CODE_SIGNING_ALLOWED=NO \
        -quiet
      ok "Simulator build succeeded"
    else
      note "Skipped. Run later with:"
      note "  swift test --package-path Balm/BalmCore"
      note "  xcodebuild build -project Balm.xcodeproj -scheme Balm -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO"
    fi
  fi
fi

step "Done - what's next"
cat <<'EOF'

Local setup is finished.

  1. In the Atlassian developer console, configure the OAuth app whose client
     ID is in Config/Secrets.xcconfig. Register balm://auth/callback and enable
     the Jira scopes listed in Balm/BalmCore/Sources/BalmAuth/OAuthConfig.swift.
  2. Put the same ATLASSIAN_CLIENT_ID and its ATLASSIAN_CLIENT_SECRET in
     Server/.env.local, then run: cd Server && bun run dev
  3. For a different BFF deployment, update BALM_BFF_BASE_URL in
     Config/Secrets.xcconfig. Keep the client secret server-side.
  4. Open Balm.xcodeproj, select your signing team, and run the Balm scheme.
  5. For TestFlight, configure the signing and App Store Connect secrets used
     by .github/workflows/ios-testflight.yml. IOS_SECRETS_XCCONFIG may override
     the committed example values for production archives.

See README.md and AGENTS.md for commands and architecture.
EOF
