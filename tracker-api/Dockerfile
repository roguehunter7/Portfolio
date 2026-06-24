# Stage 1: Build the static Go binary
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go.mod and go.sum and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source files
COPY main.go ./

# Build a highly optimized, static binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o tracker-api main.go

# Stage 2: Minimal runtime container
FROM alpine:latest

# Install ca-certificates for secure outgoing connections to Firestore API
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the compiled binary from Stage 1
COPY --from=builder /app/tracker-api .

EXPOSE 8080

CMD ["./tracker-api"]
