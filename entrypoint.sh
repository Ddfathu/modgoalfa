#!/bin/bash

USER_NAME="${SSH_USER:-dd}"
USER_PASS="${SSH_PASSWORD:-dd}"
PUBLIC_PORT="${PORT:-8080}"
SSL_INTERNAL_PORT="${SSL_INTERNAL_PORT:-2443}"

echo "[*] Mengonfigurasi Server Message Dropbear (Banner Pra-Login)..."
cat << 'EOF' > /etc/dropbear_banner
=================================================
                  SELAMAT MENIKMATI
             PREMIUM SSH SERVER DROPBEAR modssh        
=================================================
       Dilarang Torrent / DDOS / Hacking! 
                 Powered By: dedefathu
=================================================
EOF

echo "[*] Mengonfigurasi Respon Server (Pasca-Login)..."
mkdir -p /etc/profile.d
cat << 'EOF' > /etc/profile.d/99-respon-server.sh
#!/bin/bash
clear
echo -e "\e[1;36m=================================================\e[0m"
echo -e "\e[1;32m       [✓] BERHASIL TERHUBUNG KE SERVER!         \e[0m"
echo -e "\e[1;36m=================================================\e[0m"
echo -e "\e[1;37m Username     : \e[1;33m$USER\e[0m"
echo -e "\e[1;37m Waktu Server : \e[1;33m$(date)\e[0m"
echo -e "\e[1;37m OS           : \e[1;33mAlpine Linux (Dropbear Mode)\e[0m"
echo -e "\e[1;36m=================================================\e[0m"
EOF
chmod +x /etc/profile.d/99-respon-server.sh

echo "[*] Mengonfigurasi User SSH versi Alpine..."
if ! id "$USER_NAME" &>/dev/null; then
    # Perintah adduser khas Alpine (tanpa useradd)
    adduser -D -s /bin/bash "$USER_NAME"
    # Menambahkan ke sudoers versi Alpine/sudo
    echo "$USER_NAME ALL=(ALL) ALL" >> /etc/sudoers
fi
echo "$USER_NAME:$USER_PASS" | chpasswd

echo "[*] Memulai Dropbear Server..."
/usr/sbin/dropbear -p 127.0.0.1:22 -b /etc/dropbear_banner -W 65536

echo "[*] Membuat konfigurasi Stunnel..."
# Di Alpine, user/group stunnel namanya 'stunnel' (bukan stunnel4)
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

if [ -n "$CF_TUNNEL_TOKEN" ]; then
    echo "[*] Menjalankan Cloudflare Tunnel..."
    cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" &
fi

echo "[*] Memulai GOLANG TURBO TUNNEL ENGINE di Port PUBLIK $PUBLIC_PORT..."
exec env \
    PORT="$PUBLIC_PORT" \
    SSL_TARGET_HOST="127.0.0.1" \
    SSL_TARGET_PORT="$SSL_INTERNAL_PORT" \
    WS_TARGET_HOST="127.0.0.1" \
    WS_TARGET_PORT="22" \
    turbo-proxy
