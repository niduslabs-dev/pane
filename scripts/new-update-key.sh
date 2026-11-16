#!/bin/sh
# Makes Pane's update-signing key (Sparkle's EdDSA key) and stores its private half as the
# SPARKLE_ED_PRIVATE_KEY secret of the repo's `release` environment. Run once, by the person
# who owns releases; agents never run it. The private half exists only in this process's
# memory and in the secret: it is never printed, written to disk or put in a keychain.
# Prints the public half, which goes into scripts/build-app.sh as RELEASE_SPARKLE_PUBLIC_KEY.
#
# Pane's key was made on 2026-11-17 with a copy kept in the workspace's creds/ folder
# (PANE_SPARKLE_ED_PRIVATE_KEY.txt, out of git); restore from there rather than replacing it.
#
# There is no other copy. Losing the secret, or replacing it after a release, means
# installed copies refuse every later update and people must reinstall by hand; so this
# refuses to run when the secret already exists, unless given --replace.
#
# Usage: scripts/new-update-key.sh [--replace]
# Needs: gh (signed in with access to the repo's secrets) and OpenSSL 3 (macOS's own
# LibreSSL can't make Ed25519 keys; Homebrew's openssl can). OPENSSL overrides the binary.
set -eu
REPO=niduslabs-dev/pane
ENVIRONMENT=release
SECRET=SPARKLE_ED_PRIVATE_KEY
OPENSSL=${OPENSSL:-/opt/homebrew/bin/openssl}
KEY_BYTES=32
# The DER header of a PKCS#8 Ed25519 private key; the 32-byte seed follows it.
PKCS8_ED25519_PREFIX=302e020100300506032b657004220420

command -v "$OPENSSL" >/dev/null || { echo "error: $OPENSSL not found; set OPENSSL to an OpenSSL 3 binary" >&2; exit 1; }
if gh secret list --repo "$REPO" --env "$ENVIRONMENT" | grep -q "^${SECRET}[[:space:]]"; then
    [ "${1:-}" = "--replace" ] || { echo "error: $SECRET is already set for $REPO ($ENVIRONMENT). See the header before using --replace." >&2; exit 1; }
fi

# The seed in the form `sign_update --ed-key-file` reads: base64 of 32 random bytes.
SEED=$("$OPENSSL" rand -base64 "$KEY_BYTES")
PUBLIC=$({ printf '%s' "$PKCS8_ED25519_PREFIX" | xxd -r -p; printf '%s' "$SEED" | base64 -d; } |
    "$OPENSSL" pkey -inform DER -pubout -outform DER | tail -c "$KEY_BYTES" | base64)
if [ "$(printf '%s' "$PUBLIC" | base64 -d | wc -c | tr -d ' ')" != "$KEY_BYTES" ]; then
    echo "error: couldn't derive the public key; nothing was stored" >&2
    exit 1
fi
printf '%s' "$SEED" | gh secret set "$SECRET" --repo "$REPO" --env "$ENVIRONMENT"
unset SEED
echo "Stored $SECRET for $REPO ($ENVIRONMENT)."
echo "Public key (not a secret), for RELEASE_SPARKLE_PUBLIC_KEY in scripts/build-app.sh:"
echo "$PUBLIC"
