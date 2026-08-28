#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/os/config/includes.chroot/usr/lib/bedrock/validate-update-trust"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

make_cert() {
  name=$1
  subject="/CN=Bedrock update $name/"
  case $(uname -s) in MINGW*) subject="/$subject";; esac
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "$subject" \
    -keyout "$work/$name.key" -out "$work/$name.pem" >/dev/null 2>&1
}
sign() {
  name=$1
  openssl cms -sign -binary -noattr -md sha256 -in "$work/manifest" \
    -signer "$work/$name.pem" -inkey "$work/$name.key" -outform DER -out "$work/manifest.p7s"
}
verify() {
  trust=$1
  "$validator" "$trust" >/dev/null
  openssl cms -verify -binary -inform DER -in "$work/manifest.p7s" -content "$work/manifest" \
    -CAfile "$trust" -purpose any -out /dev/null >/dev/null 2>&1
}
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded: %s\n' "$*" >&2; exit 1; fi; }

make_cert current
make_cert next
make_cert unrelated
printf '{"generation":42}\n' > "$work/manifest"
cat "$work/current.pem" "$work/next.pem" > "$work/overlap.pem"

sign current
verify "$work/overlap.pem"
sign next
verify "$work/overlap.pem"
must_fail verify "$work/current.pem"

sign current
must_fail verify "$work/next.pem"
sign unrelated
must_fail verify "$work/overlap.pem"

cat "$work/current.pem" "$work/current.pem" > "$work/duplicate.pem"
cat "$work/current.pem" "$work/next.pem" "$work/unrelated.pem" > "$work/three.pem"
cp "$work/current.pem" "$work/garbage.pem"
printf 'unexpected data\n' >> "$work/garbage.pem"
ln -s "$work/current.pem" "$work/indirect.pem"
must_fail "$validator" "$work/duplicate.pem"
must_fail "$validator" "$work/three.pem"
must_fail "$validator" "$work/garbage.pem"
if [ -L "$work/indirect.pem" ]; then must_fail "$validator" "$work/indirect.pem"; fi

printf 'Update trust rotation tests passed.\n'
