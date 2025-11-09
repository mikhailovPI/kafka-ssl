#!/usr/bin/env bash
set -euo pipefail

BOOT="${BOOTSTRAP:-kafka-1:9093}"
ADMIN="${CMD_CONFIG:-/clients/admin.properties}"

echo "[setup] cluster ACLs"
kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
  --add --allow-principal User:client-producer --cluster \
  --operation Describe --operation IdempotentWrite

kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
  --add --allow-principal User:client-consumer --cluster \
  --operation Describe

# чтобы негативный тест падал по правам на ТОПИК, а не по группе
for G in cg-check-1 cg-negative; do
  kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
    --add --allow-principal User:client-consumer --group "$G" --operation Read
done

echo "[setup] topics"
for T in topic-1 topic-2; do
  kafka-topics --bootstrap-server "$BOOT" --command-config "$ADMIN" \
    --create --if-not-exists --topic "$T" --partitions 3 --replication-factor 3
done

echo "[setup] topic-1 ACLs (producer write/create/describe; consumer read/describe)"
kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
  --add --allow-principal User:client-producer --topic topic-1 \
  --operation Write --operation Create --operation Describe

kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
  --add --allow-principal User:client-consumer --topic topic-1 \
  --operation Read --operation Describe

echo "[setup] topic-2 ACLs (producer write/create/describe; consumer DENY read)"
kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
  --add --allow-principal User:client-producer --topic topic-2 \
  --operation Write --operation Create --operation Describe

kafka-acls --bootstrap-server "$BOOT" --command-config "$ADMIN" \
  --add --deny-principal User:client-consumer --topic topic-2 --operation Read

echo "[setup] verify"
echo "== topics =="
kafka-topics --bootstrap-server "$BOOT" --command-config "$ADMIN" --list || true
echo "== acls =="
kafka-acls  --bootstrap-server "$BOOT" --command-config "$ADMIN" --list  || true
echo "[setup] done"
