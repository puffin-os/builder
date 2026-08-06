#!/bin/sh
set -eu

# Generate a disposable GPG key for signing update manifests and export its
# public key so the image can verify sysupdate transfers.  The key material
# lives in .local/ alongside the mkosi Secure Boot keys.

keys_dir=${1:?keys directory required}
test -f "$keys_dir/update-pubring.gpg" && exit 0

export GNUPGHOME=$(mktemp -d)
chmod 700 "$GNUPGHOME"
trap 'rm -rf "$GNUPGHOME"' EXIT

cat > "$GNUPGHOME/batch" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: Puffin development
Name-Email: dev@puffin.invalid
Expire-Date: 0
%no-protection
%commit
EOF

gpg --batch --gen-key "$GNUPGHOME/batch"
gpg --batch --export --output "$keys_dir/update-pubring.gpg"
gpg --batch --export-secret-keys --output "$keys_dir/update-signing-key.gpg"