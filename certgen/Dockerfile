FROM eclipse-temurin:17-jdk-jammy

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY make-certs.sh /usr/local/bin/make-certs

RUN sed -i 's/\r$//' /usr/local/bin/make-certs
ENTRYPOINT ["bash", "/usr/local/bin/make-certs"]

RUN chmod +x /usr/local/bin/make-certs
