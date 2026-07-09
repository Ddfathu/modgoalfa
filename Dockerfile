# Stage 1: Kompilasi biner Go Proxy
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o turbo-proxy main.go

# Stage 2: OS Utama Alpine dengan Kombinasi Hybrid Python + Go
FROM alpine:latest

# Memasang dependensi dasar (Python3 diikutsertakan kembali demi kestabilan mux.py gerbang luar)
RUN apk add --no-cache dropbear stunnel bash curl openssl sudo python3

# Install cloudflared (Argo Tunnel)
RUN curl -fsSL -o /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

# Ambil hasil biner Go
COPY --from=builder /app/turbo-proxy /usr/local/bin/turbo-proxy
RUN chmod +x /usr/local/bin/turbo-proxy

# Buat direktori run & konfigurasi
RUN mkdir -p /var/run/dropbear /var/run/stunnel /etc/dropbear /etc/stunnel

# Buat sertifikat SSL Stunnel
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RailwaySSH/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem
RUN chown -R stunnel:stunnel /var/run/stunnel /etc/stunnel

# Salin skrip pembantu & menu management user
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY addssh delssh listssh menu /usr/local/bin/
RUN chmod +x /usr/local/bin/addssh /usr/local/bin/delssh /usr/local/bin/listssh /usr/local/bin/menu

# Salin kembali mux.py milik lu untuk memegang gerbang luar port Railway
COPY mux.py /usr/local/bin/mux.py
RUN chmod +x /usr/local/bin/mux.py

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
