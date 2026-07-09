package main

import (
	"bytes"
	"crypto/sha1"
	"encoding/base64"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"syscall"
	"time"
)

const (
	WS_MAGIC           = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	TLS_HANDSHAKE_BYTE = 0x16
)

var (
	listenPort     = getEnv("PORT", "8080")
	sslTargetHost  = getEnv("SSL_TARGET_HOST", "127.0.0.1")
	sslTargetPort  = getEnv("SSL_TARGET_PORT", "2443")
	sshTargetHost  = getEnv("WS_TARGET_HOST", "127.0.0.1")
	sshTargetPort  = getEnv("WS_TARGET_PORT", "22")
)

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

func tuneSocket(conn net.Conn) {
	tcpConn, ok := conn.(*net.TCPConn)
	if !ok {
		return
	}
	rawConn, err := tcpConn.SyscallConn()
	if err != nil {
		return
	}
	rawConn.Control(func(fd uintptr) {
		syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_NODELAY, 1)
		syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_RCVBUF, 524288)
		syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_SNDBUF, 524288)
		syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_KEEPALIVE, 1)
		syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPIDLE, 30)
		syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPINTVL, 10)
		syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPCNT, 12)
	})
}

func main() {
	log.Println("================================================================")
	log.Printf("GOLANG TURBO TUNNEL ENGINE ACTIVE ON PORT %s\n", listenPort)
	log.Println("================================================================")

	listener, err := net.Listen("tcp", "0.0.0.0:"+listenPort)
	if err != nil {
		log.Fatalf("Gagal menjalankan listener: %v", err)
	}
	defer listener.Close()

	for {
		clientConn, err := listener.Accept()
		if err != nil {
			continue
		}
		tuneSocket(clientConn)
		go handleClient(clientConn)
	}
}

func handleClient(clientConn net.Conn) {
	defer clientConn.Close()

	// Timeout baca longgar 1.5 detik biar payload trik berlapis gak kepotong
	clientConn.SetReadDeadline(time.Now().Add(1500 * time.Millisecond))
	headerBuf := make([]byte, 16384)
	n, err := clientConn.Read(headerBuf)
	clientConn.SetReadDeadline(time.Time{})

	if err != nil || n == 0 {
		return
	}

	rawPayload := headerBuf[:n]

	// JALUR 1: Jika traffic adalah SSL/TLS murni (Stunnel)
	if rawPayload[0] == TLS_HANDSHAKE_BYTE {
		targetConn, err := net.Dial("tcp", sslTargetHost+":"+sslTargetPort)
		if err != nil {
			return
		}
		defer targetConn.Close()
		tuneSocket(targetConn)

		targetConn.Write(rawPayload)
		go io.Copy(targetConn, clientConn)
		io.Copy(clientConn, targetConn)
		return
	}

	// JALUR 2: WEBSOCKET HANDSHAKE (Logika Contains Anti-502)
	rawText := string(rawPayload)
	wsKey := ""
	
	lines := strings.Split(rawText, "\r\n")
	for _, line := range lines {
		if strings.Contains(strings.ToLower(line), "sec-websocket-key") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				wsKey = strings.TrimSpace(parts[1])
				break
			}
		}
	}

	if wsKey == "" {
		wsKey = base64.StdEncoding.EncodeToString([]byte(time.Now().String() + "turbo-salt"))
	}

	h := sha1.New()
	h.Write([]byte(wsKey + WS_MAGIC))
	acceptKey := base64.StdEncoding.EncodeToString(h.Sum(nil))
	
	// String murni tanpa butuh library "fmt"
	response := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n"
	
	clientConn.Write([]byte(response))

	// Hubungkan ke Dropbear internal port 22
	sshConn, err := net.Dial("tcp", sshTargetHost+":"+sshTargetPort)
	if err != nil {
		return
	}
	defer sshConn.Close()
	tuneSocket(sshConn)

	// Pipa 1: HP -> SSH Server (Enhanced Payload Matcher)
	go func() {
		firstPacket := true
		buf := make([]byte, 65536)
		for {
			rn, err := clientConn.Read(buf)
			if err != nil {
				return
			}
			data := buf[:rn]
			if firstPacket {
				idx := bytes.Index(data, []byte("SSH-"))
				if idx != -1 {
					sshConn.Write(data[idx:])
					firstPacket = false
				}
			} else {
				sshConn.Write(data)
			}
		}
	}()

	// Pipa 2: SSH Server -> HP (Injeksi Heartbeat \x89\x00 Perangko)
	bufDown := make([]byte, 65536)
	for {
		sshConn.SetReadDeadline(time.Now().Add(5 * time.Second))
		rn, err := sshConn.Read(bufDown)

		if err, ok := err.(net.Error); ok && err.Timeout() {
			clientConn.Write([]byte{0x89, 0x00})
			continue
		}
		if err != nil {
			return
		}
		clientConn.SetReadDeadline(time.Time{})
		_, err = clientConn.Write(bufDown[:rn])
		if err != nil {
			return
		}
	}
}
