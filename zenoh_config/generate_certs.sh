#!/bin/bash
# Self-signed certificate generation for Zenoh QUIC transport (exp4_quic)
# Run ONCE on a single machine, then copy /etc/zenoh/certs/ to all 5 drones
# (every node uses the same key pair — this is fine for a closed experiment LAN).
#
# Usage:
#   sudo ./generate_certs.sh
#   sudo scp -r /etc/zenoh/certs/  drone-N:/etc/zenoh/   # for each drone

set -e

CERT_DIR="/etc/zenoh/certs"
DAYS=3650        # 10 years - experiment is short-lived but renewing is annoying
KEY_BITS=2048    # 4096 is overkill for an experiment

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# 1. CA (Certificate Authority)
openssl genrsa -out ca.key $KEY_BITS
openssl req -x509 -new -nodes -key ca.key -sha256 -days $DAYS \
    -out ca.pem -subj "/CN=zenoh-experiment-ca"

# 2. Server cert signed by the CA (used by every node for both listen and connect)
openssl genrsa -out server.key $KEY_BITS
openssl req -new -key server.key -out server.csr \
    -subj "/CN=zenoh-node"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
    -out server.pem -days $DAYS -sha256

# Cleanup intermediates
rm -f server.csr ca.srl

# Permissions: keys readable only by owner
chmod 600 *.key
chmod 644 *.pem

echo "Certs generated in $CERT_DIR:"
ls -la "$CERT_DIR"
echo
echo "Verify chain:"
openssl verify -CAfile ca.pem server.pem
