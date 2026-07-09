# =====================================================================
# STAGE 1: Kompilasi Source Code Golang Menjadi Biner Murni
# =====================================================================
FROM golang:1.21-alpine AS builder
WORKDIR /app
# Menyalin file main.go buatan kita ke dalam stage build
COPY main.go .
# Build biner dengan optimasi ukuran paling kecil, tanpa dependensi eksternal (CGO_ENABLED=0)
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o turbo-proxy main.go

# =====================================================================
# STAGE 2: Base OS Utama Menggunakan Ubuntu Bawaan Lu
# =====================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# --- Menginstal dependensi dasar (Python3 DIHAPUS karena diganti Go) ---
RUN apt-get update && apt-get install -y \
    dropbear \
    stunnel4 \
    openssl \
    sudo \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install cloudflared (untuk Argo Tunnel, jalur WS)
RUN curl -fsSL -o /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

# 🔥 AMBIL BINER GOLANG: Memindahkan hasil compile dari Stage 1 ke folder bin utama
COPY --from=builder /app/turbo-proxy /usr/local/bin/turbo-proxy
RUN chmod +x /usr/local/bin/turbo-proxy

# Membuat semua direktori run & konfigurasi yang dibutuhkan secara lengkap
RUN mkdir -p /var/run/dropbear /var/run/stunnel /etc/dropbear /etc/stunnel

# Membuat sertifikat SSL untuk Stunnel
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RailwaySSH/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

# Atur kepemilikan folder agar Stunnel tidak mengalami 'Permission Denied' saat membuat PID
RUN chown -R stunnel4:stunnel4 /var/run/stunnel /etc/stunnel

# Menyalin script utama entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Menyalin script manajemen user bawaan lu (addssh, delssh, listssh, menu)
COPY addssh delssh listssh menu /usr/local/bin/
RUN chmod +x /usr/local/bin/addssh /usr/local/bin/delssh /usr/local/bin/listssh /usr/local/bin/menu

# ⚠️ CATATAN: File 'ws-proxy.py' dan 'mux.py' SUDAH TIDAK DI-COPY LAGI
# Karena fungsinya digantikan penuh oleh biner /usr/local/bin/turbo-proxy

# Cukup SATU port publik utama
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
