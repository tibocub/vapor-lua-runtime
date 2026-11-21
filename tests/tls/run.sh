#!/bin/sh
# TLS test against a local openssl s_server: a private CA, a server certificate for "localhost", and a second server with a certificate for another name.
# usage: sh tests/tls/run.sh        (VLR=./vlr by default; skipped without openssl)
VLR=${VLR:-./vlr}
command -v openssl >/dev/null 2>&1 || { echo "skip tls (no openssl)"; exit 0; }
d=$(mktemp -d "${TMPDIR:-/tmp}/vlr-tls.XXXXXX"); trap 'kill $p1 $p2 2>/dev/null; rm -rf "$d"' EXIT
cd "$d" || exit 1
mk() { # name, cn/san
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1.key" -out "$1.crt" -days 2 -subj "/CN=$2" \
    -addext "subjectAltName=DNS:$2" -addext "basicConstraints=critical,CA:TRUE" >/dev/null 2>&1
}
mk good localhost; mk other example.invalid
P1=${TLS_PORT1:-18443}; P2=${TLS_PORT2:-18444}
openssl s_server -accept $P1 -cert good.crt -key good.key -www -quiet >good.log 2>&1 &
p1=$!
openssl s_server -accept $P2 -cert other.crt -key other.key -www -quiet >other.log 2>&1 &
p2=$!
sleep 1
cd - >/dev/null
TLS_DIR=$d TLS_GOOD=$P1 TLS_OTHER=$P2 $VLR tests/tls.lua && echo "ok   tls"
