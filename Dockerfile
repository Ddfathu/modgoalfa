# Stage 1: Build biner Go
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o turbo-proxy main.go

# Stage 2: OS Utama murni Alpine
FROM alpine:latest

# Install dependensi dasar versi Alpine (Tanpa Python, Pakai stunnel murni)
RUN apk add --no-cache dropbear stunnel bash curl openssl sudo

# Install cloudflared (Argo Tunnel)
RUN curl -fsSL -o /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

# Ambil biner Go dari Stage 1
COPY --from=builder /app/turbo-proxy /usr/local/bin/turbo-proxy
RUN chmod +x /usr/local/bin/turbo-proxy

# Buat direktori run & konfigurasi
RUN mkdir -p /var/run/dropbear /var/run/stunnel /etc/dropbear /etc/stunnel

# Buat sertifikat SSL untuk Stunnel
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RailwaySSH/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

# Atur izin kepemilikan folder khusus user stunnel di Alpine
RUN chown -R stunnel:stunnel /var/run/stunnel /etc/stunnel

# Salin skrip utama & manajemen user
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY addssh delssh listssh menu /usr/local/bin/
RUN chmod +x /usr/local/bin/addssh /usr/local/bin/delssh /usr/local/bin/listssh /usr/local/bin/menu

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
