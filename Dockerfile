# syntax=docker/dockerfile:1

FROM golang:1.24-alpine AS build

WORKDIR /app

COPY container_src/go.mod ./
RUN go mod download

COPY container_src/*.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o /server

FROM alpine:3.20

# Install ca-certificates first to fix SSL verification, then install other packages
RUN apk update && \
    apk add --no-cache ca-certificates && \
    apk add --no-cache fuse fuse-dev curl bash

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; fi && \
    if [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; fi && \
    VERSION=$(curl -s https://api.github.com/repos/tigrisdata/tigrisfs/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4) && \
    curl -L "https://github.com/tigrisdata/tigrisfs/releases/download/${VERSION}/tigrisfs_${VERSION#v}_linux_${ARCH}.tar.gz" -o /tmp/tigrisfs.tar.gz && \
    tar -xzf /tmp/tigrisfs.tar.gz -C /usr/local/bin/ && \
    rm /tmp/tigrisfs.tar.gz && \
    chmod +x /usr/local/bin/tigrisfs

COPY --from=build /server /server

RUN printf '#!/bin/sh\n\
    set -e\n\
    \n\
    mkdir -p "$HOME/mnt/r2/${BUCKET_NAME}"\n\
    \n\
    R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"\n\
    echo "Mounting bucket ${BUCKET_NAME}..."\n\
    /usr/local/bin/tigrisfs --endpoint "${R2_ENDPOINT}" -f "${BUCKET_NAME}" "$HOME/mnt/r2/${BUCKET_NAME}${PREFIX:+:${PREFIX}}" &\n\
    sleep 3\n\
    \n\
    echo "Starting server on :8080"\n\
    exec /server\n\
    ' > /startup.sh && chmod +x /startup.sh

EXPOSE 8080

CMD ["/startup.sh"]
