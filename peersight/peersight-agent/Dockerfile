FROM golang:1.23-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /peersight-agent ./cmd/agent

FROM alpine:3.20
RUN apk add --no-cache ca-certificates wireguard-tools
COPY --from=builder /peersight-agent /usr/local/bin/peersight-agent
ENTRYPOINT ["peersight-agent"]
