#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Kafka SSL cert generator (OS-agnostic, Docker-friendly)
# - All console output is English-only (no Cyrillic)
# - Idempotent: re-running won't break existing artifacts
# - SANs include CN, localhost, host.docker.internal, 127.0.0.1
# - Generates PKCS12 keystore/truststore for brokers & clients
# ============================================================

# -------- Configuration (override via env) ------------------
OUT_DIR="${OUT_DIR:-/secrets}"
PASSWORD="${PASSWORD:-changeit}"

BROKERS="${BROKERS:-kafka-1,kafka-2,kafka-3}"
CLIENTS="${CLIENTS:-admin,client-producer,client-consumer}"

CA_CN="${CA_CN:-Demo-Root-CA}"
CA_DAYS="${CA_DAYS:-3650}"
KEY_SIZE="${KEY_SIZE:-2048}"
CERT_DAYS="${CERT_DAYS:-1825}"

EXTRA_SAN_DNS="${EXTRA_SAN_DNS:-host.docker.internal}"
EXTRA_SAN_IP="${EXTRA_SAN_IP:-}"  # e.g. "10.0.2.2,192.168.1.100"

# -------- Helpers -------------------------------------------
log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERROR] $*" >&2; }

mkdir -p "${OUT_DIR}/ca" "${OUT_DIR}/brokers" "${OUT_DIR}/clients"

mk_san_cfg() {
  local cn="$1"
  local file="$2"

  local dns_list=("${cn}" "localhost")
  if [[ -n "${EXTRA_SAN_DNS}" ]]; then
    IFS=',' read -ra _dns <<< "${EXTRA_SAN_DNS}"
    dns_list+=("${_dns[@]}")
  fi

  local ip_list=("127.0.0.1")
  if [[ -n "${EXTRA_SAN_IP}" ]]; then
    IFS=',' read -ra _ips <<< "${EXTRA_SAN_IP}"
    ip_list+=("${_ips[@]}")
  fi

  {
    cat <<EOF
[ req ]
default_bits       = ${KEY_SIZE}
distinguished_name = dn
req_extensions     = req_ext
prompt             = no

[ dn ]
C  = US
O  = DemoOrg
OU = Kafka
CN = ${cn}

[ req_ext ]
subjectAltName = @alt_names

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer
basicConstraints      = CA:FALSE
keyUsage              = digitalSignature, keyEncipherment
extendedKeyUsage      = serverAuth, clientAuth
subjectAltName        = @alt_names

[ alt_names ]
EOF
    local idx=1
    for d in "${dns_list[@]}"; do
      echo "DNS.${idx} = ${d}"
      idx=$((idx+1))
    done
    idx=1
    for ip in "${ip_list[@]}"; do
      echo "IP.${idx} = ${ip}"
      idx=$((idx+1))
    done
  } > "${file}"
}

# -------- Root CA -------------------------------------------
if [[ ! -f "${OUT_DIR}/ca/ca.key" ]] || [[ ! -f "${OUT_DIR}/ca/ca.crt" ]]; then
  log "Creating Root CA private key and certificate..."
  openssl genrsa -out "${OUT_DIR}/ca/ca.key" 4096
  openssl req -x509 -new -nodes -sha256 -days "${CA_DAYS}" \
    -key "${OUT_DIR}/ca/ca.key" \
    -subj "/C=US/O=DemoOrg/OU=Kafka/CN=${CA_CN}" \
    -out "${OUT_DIR}/ca/ca.crt"
  log "Root CA created."
else
  log "Root CA already exists, skipping."
fi

if [[ ! -f "${OUT_DIR}/ca/ca.srl" ]]; then
  echo "01" > "${OUT_DIR}/ca/ca.srl"
fi

# -------- Brokers -------------------------------------------
IFS=',' read -ra BK <<< "${BROKERS}"
for b in "${BK[@]}"; do
  BDIR="${OUT_DIR}/brokers/${b}"
  mkdir -p "${BDIR}"

  if [[ -f "${BDIR}/${b}.keystore.p12" ]]; then
    log "Broker '${b}': keystore already exists, skipping key generation."
  else
    log "Broker '${b}': generating key and CSR..."
    openssl genrsa -out "${BDIR}/${b}.key" "${KEY_SIZE}"
    TMP_CFG="$(mktemp)"; trap 'rm -f "${TMP_CFG}"' EXIT
    mk_san_cfg "${b}" "${TMP_CFG}"
    openssl req -new -key "${BDIR}/${b}.key" -out "${BDIR}/${b}.csr" -config "${TMP_CFG}"

    log "Broker '${b}': signing certificate with Root CA..."
    openssl x509 -req -sha256 -days "${CERT_DAYS}" \
      -in "${BDIR}/${b}.csr" \
      -CA "${OUT_DIR}/ca/ca.crt" -CAkey "${OUT_DIR}/ca/ca.key" -CAserial "${OUT_DIR}/ca/ca.srl" -CAcreateserial \
      -out "${BDIR}/${b}.crt" -extensions v3_ext -extfile "${TMP_CFG}"

    log "Broker '${b}': assembling PKCS12 keystore..."
    openssl pkcs12 -export \
      -in "${BDIR}/${b}.crt" -inkey "${BDIR}/${b}.key" \
      -certfile "${OUT_DIR}/ca/ca.crt" \
      -out "${BDIR}/${b}.keystore.p12" -name "${b}" -passout pass:"${PASSWORD}"
  fi

  # Truststore (always ensure CA present)
  if [[ -f "${BDIR}/truststore.p12" ]]; then
    log "Broker '${b}': ensuring CA is present in truststore..."
    keytool -delete -alias CARoot \
      -keystore "${BDIR}/truststore.p12" \
      -storepass "${PASSWORD}" -storetype PKCS12 >/dev/null 2>&1 || true
  else
    log "Broker '${b}': creating truststore..."
  fi
  keytool -importcert -noprompt \
    -keystore "${BDIR}/truststore.p12" \
    -storetype PKCS12 \
    -storepass "${PASSWORD}" \
    -alias CARoot \
    -file "${OUT_DIR}/ca/ca.crt"

  log "Broker '${b}': keystore/truststore ready."
done

# -------- Clients -------------------------------------------
IFS=',' read -ra CL <<< "${CLIENTS}"
for c in "${CL[@]}"; do
  CDIR="${OUT_DIR}/clients/${c}"
  mkdir -p "${CDIR}"

  if [[ -f "${CDIR}/${c}.keystore.p12" ]]; then
    log "Client '${c}': keystore already exists, skipping key generation."
  else
    log "Client '${c}': generating key and CSR..."
    openssl genrsa -out "${CDIR}/${c}.key" "${KEY_SIZE}"
    TMP_CFG="$(mktemp)"; trap 'rm -f "${TMP_CFG}"' EXIT
    # For clients we still include SANs so they can be used in TLS client-auth contexts
    mk_san_cfg "${c}" "${TMP_CFG}"
    openssl req -new -key "${CDIR}/${c}.key" -out "${CDIR}/${c}.csr" -config "${TMP_CFG}"

    log "Client '${c}': signing certificate with Root CA..."
    openssl x509 -req -sha256 -days "${CERT_DAYS}" \
      -in "${CDIR}/${c}.csr" \
      -CA "${OUT_DIR}/ca/ca.crt" -CAkey "${OUT_DIR}/ca/ca.key" -CAserial "${OUT_DIR}/ca/ca.srl" -CAcreateserial \
      -out "${CDIR}/${c}.crt" -extensions v3_ext -extfile "${TMP_CFG}"

    log "Client '${c}': assembling PKCS12 keystore..."
    openssl pkcs12 -export \
      -in "${CDIR}/${c}.crt" -inkey "${CDIR}/${c}.key" \
      -certfile "${OUT_DIR}/ca/ca.crt" \
      -out "${CDIR}/${c}.keystore.p12" -name "${c}" -passout pass:"${PASSWORD}"
  fi

  # Truststore (ensure CA present)
  if [[ -f "${CDIR}/truststore.p12" ]]; then
    log "Client '${c}': ensuring CA is present in truststore..."
    keytool -delete -alias CARoot \
      -keystore "${CDIR}/truststore.p12" \
      -storepass "${PASSWORD}" -storetype PKCS12 >/dev/null 2>&1 || true
  else
    log "Client '${c}': creating truststore..."
  fi
  keytool -importcert -noprompt \
    -keystore "${CDIR}/truststore.p12" \
    -storetype PKCS12 \
    -storepass "${PASSWORD}" \
    -alias CARoot \
    -file "${OUT_DIR}/ca/ca.crt"

  log "Client '${c}': keystore/truststore ready."
done

# -------- Shared convenience (optional) ---------------------
mkdir -p "${OUT_DIR}/clients/_shared"
cp -f "${OUT_DIR}/ca/ca.crt" "${OUT_DIR}/clients/_shared/"

log "All certificates and stores are ready."
log "Root CA: ${OUT_DIR}/ca/ca.crt"
log "Brokers: ${BROKERS}"
log "Clients: ${CLIENTS}"
