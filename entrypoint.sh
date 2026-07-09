#!/bin/bash

USER_NAME="${SSH_USER:-dd}"
USER_PASS="${SSH_PASSWORD:-dd}"
PUBLIC_PORT="${PORT:-8080}"
SSL_INTERNAL_PORT="${SSL_INTERNAL_PORT:-2443}"
WS_INTERNAL_PORT="${WS_INTERNAL_PORT:-8880}"

echo "[*] Mengonfigurasi Server Message Dropbear (Banner)..."
cat << 'EOF' > /etc/dropbear_banner
=================================================
                  SELAMAT MENIKMATI
             PREMIUM SSH SERVER DROPBEAR modssh        
=================================================
       Dilarang Torrent / DDOS / Hacking! 
                 Powered By: dedefathu
=================================================
EOF

echo "[*] Mengonfigurasi User SSH versi Alpine..."
if ! id "$USER_NAME" &>/dev/null; then
    adduser -D -s /bin/bash "$USER_NAME"
    echo "$USER_NAME ALL=(ALL) ALL" >> /etc/sudoers
fi
echo "$USER_NAME:$USER_PASS" | chpasswd

# 🔥 PERBAIKAN UTAMA: Wajib generate host keys agar Dropbear di Alpine mau hidup
echo "[*] Generate Dropbear Host Keys (Alpine Mode)..."
mkdir -p /etc/dropbear
if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
fi

echo "[*] Memulai Dropbear Server di Port Lokal 22..."
/usr/sbin/dropbear -p 127.0.0.1:22 -b /etc/dropbear_banner -W 65536

echo "[*] Membuat konfigurasi Stunnel..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4
setuid = stunnel
setgid = stunnel

[ssh-ssl]
accept = 127.0.0.1:$SSL_INTERNAL_PORT
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel..."
stunnel /etc/stunnel/stunnel.conf &

echo "[*] Memulai WebSocket Proxy (Python Engine) di Port $WS_INTERNAL_PORT..."
WS_PORT="$WS_INTERNAL_PORT" WS_TARGET_HOST="127.0.0.1" WS_TARGET_PORT="22" \
    python3 /usr/local/bin/ws-proxy.py &

if [ -n "$CF_TUNNEL_TOKEN" ]; then
    echo "[*] Menjalankan Cloudflare Tunnel..."
    cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" &
fi

echo "[*] Memulai Multiplexer Gerbang Utama di Port PUBLIK $PUBLIC_PORT..."
exec env \
    PORT="$PUBLIC_PORT" \
    SSL_TARGET_HOST="127.0.0.1" SSL_TARGET_PORT="$SSL_INTERNAL_PORT" \
    WS_MUX_TARGET_HOST="127.0.0.1" WS_MUX_TARGET_PORT="$WS_INTERNAL_PORT" \
    python3 /usr/local/bin/mux.py