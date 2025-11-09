# Kafka SSL Cluster (3 brokers) + ACL

Готовый кластер Kafka из 3 брокеров с SSL, ACL и повторяемыми скриптами:
- выпуск сертификатов и keystore/truststore для брокеров и клиентов;
- поднятие кластера (ZooKeeper + 3 брокера);
- создание топиков и ACL;
- смоук-тесты продюсера/консьюмера.

## Состав проекта
```
├─ docker-compose.yml
├─ .env # переменные окружения (порты, пароль хранилищ)
├─ certgen/ # Dockerfile и скрипты выпуска сертификатов
├─ secrets/ # сюда certgen кладёт keystore/truststore
├─ clients/ # admin.properties, producer.properties, consumer.properties
├─ kafka/
│ ├─ broker-1/server.properties
│ ├─ broker-2/server.properties
│ └─ broker-3/server.properties
└─ init/
   ├─ setup-env.sh # создание топиков и ACL
   └─ test.sh # смоук-тесты (produce/consume)
```

## Требования

- Docker Desktop / Docker Engine + Docker Compose
- Порты на хосте (пример в `.env`):
  ```dotenv
  SSL_STORE_PASSWORD=changeit
  KAFKA1_PORT=19094
  KAFKA2_PORT=29094
  KAFKA3_PORT=39094

# Старт
### 1) Выпустить сертификаты (разово)
```
docker compose run --rm certgen
```

### 2) Поднять ZooKeeper и 3 брокера
```
docker compose up -d zookeeper kafka-1 kafka-2 kafka-3
```

### 3) Создать топики и ACL
```
docker compose exec -T kafka-1 bash -lc `
'cat /init/setup-env.sh | sed "s/\r$//" | BOOTSTRAP=kafka-1:9093 CMD_CONFIG=/clients/admin.properties bash -s'
```

### 4) Прогнать тесты 
```
docker compose exec -T kafka-1 bash -lc `
'cat /init/test.sh | sed "s/\r$//" | BOOTSTRAP=kafka-1:9093 bash -s'
```