FROM alpine:latest

# Pasang dependensi murni untuk Alpine + Python3
RUN apk add --no-cache dropbear stunnel bash curl openssl sudo python3

# Install cloudflared (Argo Tunnel)
RUN curl -fsSL -o /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

# Buat direktori run & konfigurasi
RUN mkdir -p /var/run/dropbear /var/run/stunnel /etc/dropbear /etc/stunnel

# Buat sertifikat SSL Stunnel
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RailwaySSH/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem
RUN chown -R stunnel:stunnel /var/run/stunnel /etc/stunnel

# Salin script utama entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Salin script manajemen user bawaan lu (addssh, delssh, listssh, menu)
COPY addssh delssh listssh menu /usr/local/bin/
RUN chmod +x /usr/local/bin/addssh /usr/local/bin/delssh /usr/local/bin/listssh /usr/local/bin/menu

# Salin script core proxy Python murni yang toleran terhadap dual-request payload lu
COPY ws-proxy.py /usr/local/bin/ws-proxy.py
RUN chmod +x /usr/local/bin/ws-proxy.py

COPY mux.py /usr/local/bin/mux.py
RUN chmod +x /usr/local/bin/mux.py

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]