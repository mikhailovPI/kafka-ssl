#!/usr/bin/env bash
set -euo pipefail

BOOT="${BOOTSTRAP:-kafka-1:9093}"
P="/clients/producer.properties"
C="/clients/consumer.properties"

echo "[test] produce -> topic-1"
printf "t1-ok\n" | kafka-console-producer \
  --bootstrap-server "$BOOT" --producer.config "$P" --topic topic-1 1>/dev/null

echo "[test] consume <- topic-1 (1 msg)"
kafka-console-consumer \
  --bootstrap-server "$BOOT" --consumer.config "$C" \
  --topic topic-1 --group cg-check-1 \
  --from-beginning --max-messages 1 --timeout-ms 10000

echo "[test] produce -> topic-2"
printf "t2-ok\n" | kafka-console-producer \
  --bootstrap-server "$BOOT" --producer.config "$P" --topic topic-2 1>/dev/null

echo "[test] negative: consume <- topic-2 (ожидаем пусто/ошибку/таймаут)"
set +e
kafka-console-consumer \
  --bootstrap-server "$BOOT" --consumer.config "$C" \
  --topic topic-2 --group cg-negative \
  --from-beginning --max-messages 1 --timeout-ms 5000
rc=$?
set -e
echo "[test] consumer exit code for topic-2 = $rc (не 0 или пустой вывод — корректный негативный кейс)"
echo "[test] done"
