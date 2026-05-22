FROM golang:1.23-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /peersight-broker ./cmd/broker

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=builder /peersight-broker /usr/local/bin/peersight-broker
ENTRYPOINT ["peersight-broker"]
