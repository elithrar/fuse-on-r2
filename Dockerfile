# syntax=docker/dockerfile:1

ARG TIGRISFS_VERSION=v1.2.1
ARG TIGRISFS_SHA256_AMD64=9fd6e7a9f3e7d86571ea55c66459205e94dfa5f6a25887d7e95c0a46f7641ed4
ARG TIGRISFS_SHA256_ARM64=f446e4cdf23b896ccad2efe9de0499e20f93dc44f4e7d8b38b07b257877aa185

FROM alpine:3.23 AS tigrisfs

ARG TARGETARCH
ARG TIGRISFS_VERSION
ARG TIGRISFS_SHA256_AMD64
ARG TIGRISFS_SHA256_ARM64

RUN apk add --no-cache ca-certificates curl \
    && case "${TARGETARCH}" in \
        amd64) TIGRISFS_SHA256="${TIGRISFS_SHA256_AMD64}" ;; \
        arm64) TIGRISFS_SHA256="${TIGRISFS_SHA256_ARM64}" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL \
        "https://github.com/tigrisdata/tigrisfs/releases/download/${TIGRISFS_VERSION}/tigrisfs_${TIGRISFS_VERSION#v}_linux_${TARGETARCH}.tar.gz" \
        -o /tmp/tigrisfs.tar.gz \
    && printf '%s  %s\n' "${TIGRISFS_SHA256}" /tmp/tigrisfs.tar.gz | sha256sum -c - \
    && mkdir /out \
    && tar -xzf /tmp/tigrisfs.tar.gz -C /out tigrisfs

FROM golang:1.26-alpine3.23 AS build

WORKDIR /app

COPY container_src/go.* ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY container_src/ ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    mkdir -p /out \
    && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server .

FROM alpine:3.23

RUN apk add --no-cache ca-certificates fuse

COPY --from=tigrisfs --chmod=0755 /out/tigrisfs /usr/local/bin/tigrisfs
COPY --from=build --chmod=0755 /out/server /server
COPY --chmod=0755 container_src/startup.sh /startup.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1

STOPSIGNAL SIGTERM

CMD ["/startup.sh"]
