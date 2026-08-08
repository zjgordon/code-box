#!/usr/bin/env bash
# Generate a private CA plus server/client TLS certs for sandbox-dind <-> code-box.
# Run once on the host before first bring-up. Rotate by re-running and recreating both stacks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERTS="${CERTS_DIR:-$ROOT/certs}"
DAYS="${CERT_DAYS:-825}"
CN_SERVER="${SERVER_CN:-sandbox-dind}"

CA_DIR="$CERTS/ca"
SERVER_DIR="$CERTS/server"
CLIENT_DIR="$CERTS/client"

mkdir -p "$CA_DIR" "$SERVER_DIR" "$CLIENT_DIR"

umask 077

if [[ -f "$CA_DIR/ca.pem" && -f "$CA_DIR/ca-key.pem" && "${FORCE:-}" != "1" ]]; then
  echo "CA already exists at $CA_DIR (set FORCE=1 to regenerate everything)."
else
  openssl genrsa -out "$CA_DIR/ca-key.pem" 4096
  openssl req -x509 -new -nodes -key "$CA_DIR/ca-key.pem" -sha256 -days "$DAYS" \
    -subj "/CN=code-box-dind-ca" -out "$CA_DIR/ca.pem"
fi

# Server certificate (SAN: sandbox-dind, localhost)
openssl genrsa -out "$SERVER_DIR/server-key.pem" 4096
openssl req -new -key "$SERVER_DIR/server-key.pem" -subj "/CN=${CN_SERVER}" \
  -out "$SERVER_DIR/server.csr"
cat > "$SERVER_DIR/server-ext.cnf" <<EOF
subjectAltName = DNS:${CN_SERVER},DNS:localhost,IP:127.0.0.1
extendedKeyUsage = serverAuth
EOF
openssl x509 -req -in "$SERVER_DIR/server.csr" -CA "$CA_DIR/ca.pem" -CAkey "$CA_DIR/ca-key.pem" \
  -CAcreateserial -out "$SERVER_DIR/server-cert.pem" -days "$DAYS" -sha256 \
  -extfile "$SERVER_DIR/server-ext.cnf"
cp "$CA_DIR/ca.pem" "$SERVER_DIR/ca.pem"
rm -f "$SERVER_DIR/server.csr" "$SERVER_DIR/server-ext.cnf"

# Client certificate (Docker DOCKER_CERT_PATH layout: ca.pem, cert.pem, key.pem)
openssl genrsa -out "$CLIENT_DIR/key.pem" 4096
openssl req -new -key "$CLIENT_DIR/key.pem" -subj "/CN=code-box-client" \
  -out "$CLIENT_DIR/client.csr"
cat > "$CLIENT_DIR/client-ext.cnf" <<EOF
extendedKeyUsage = clientAuth
EOF
openssl x509 -req -in "$CLIENT_DIR/client.csr" -CA "$CA_DIR/ca.pem" -CAkey "$CA_DIR/ca-key.pem" \
  -CAcreateserial -out "$CLIENT_DIR/cert.pem" -days "$DAYS" -sha256 \
  -extfile "$CLIENT_DIR/client-ext.cnf"
cp "$CA_DIR/ca.pem" "$CLIENT_DIR/ca.pem"
rm -f "$CLIENT_DIR/client.csr" "$CLIENT_DIR/client-ext.cnf" "$CA_DIR/ca.srl"

chmod 644 "$CA_DIR/ca.pem" "$SERVER_DIR/ca.pem" "$SERVER_DIR/server-cert.pem" \
  "$CLIENT_DIR/ca.pem" "$CLIENT_DIR/cert.pem"
chmod 600 "$CA_DIR/ca-key.pem" "$SERVER_DIR/server-key.pem" "$CLIENT_DIR/key.pem"

echo "Wrote TLS material under $CERTS"
echo "  server: $SERVER_DIR/{ca,server-cert,server-key}.pem"
echo "  client: $CLIENT_DIR/{ca,cert,key}.pem"
