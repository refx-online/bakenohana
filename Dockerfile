FROM crystallang/crystal:1.13.3 AS builder
WORKDIR /app

COPY shard.yml shard.lock* ./
RUN shards install --production

COPY . .
RUN mkdir -p bin && crystal build --release src/bakenohana.cr -o bin/bakenohana

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libpcre2-8-0 \
    libgc1 \
    libevent-2.1-7 \
    libxml2 \
    zlib1g \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/bin/bakenohana ./

CMD ["./bakenohana"]
