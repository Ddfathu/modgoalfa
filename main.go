package main

import (
	"bytes"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"syscall"
	"time"
)

const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

var (
	// Alpine-friendly port binding (menggunakan port internal proxy)
	listenPort = getEnv("WS_PORT", "8880")
	targetHost = getEnv("WS_TARGET_HOST", "127.0.0.1")
	targetPort = getEnv("WS_TARGET_PORT", "22")
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
	log.Printf("[go-ws] Memulai Turbo WS Proxy pada port %s -> SSH %s\n", listenPort, targetPort)
	
	// Binding tanpa menentukan IP "0.0.0.0" agar dual-stack IPv4/IPv6 Alpine aktif otomatis
	listener, err := net.Listen("tcp", ":"+listenPort)
	if err != nil {
		log.Fatalf("[go-ws] Gagal binding port: %v", err)
	}
	defer listener.Close()

	for {
		clientConn, err := listener.Accept()
		if err != nil {
			continue
		}
		tuneSocket(clientConn)
		go handleWebSocket(clientConn)
	}
}

func handleWebSocket(clientConn net.Conn) {
	defer clientConn.Close()

	// Baca jabat tangan HTTP/WS Custom
	clientConn.SetReadDeadline(time.Now().Add(3 * time.Second))
	headerBuf := make([]byte, 16384)
	n, err := clientConn.Read(headerBuf)
	clientConn.SetReadDeadline(time.Time{})

	if err != nil || n == 0 {
		return
	}

	rawText := string(headerBuf[:n])
	wsKey := ""
	for _, line := range strings.Split(rawText, "\r\n") {
		if strings.Contains(strings.ToLower(line), "sec-websocket-key") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				wsKey = strings.TrimSpace(parts[1])
				break
			}
		}
	}

	if wsKey == "" {
		wsKey = base64.StdEncoding.EncodeToString([]byte(time.Now().String()))
	}

	h := sha1.New()
	h.Write([]byte(wsKey + WS_MAGIC))
	acceptKey := base64.StdEncoding.EncodeToString(h.Sum(nil))

	// Respon standard HTTP murni tanpa masking biner palsu
	response := fmt.Sprintf("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n", acceptKey)
	clientConn.Write([]byte(response))

	// Dial ke Dropbear internal port 22
	sshConn, err := net.Dial("tcp", targetHost+":"+targetPort)
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
		sshConn.SetReadDeadline(time.Time{})
		_, err = clientConn.Write(bufDown[:rn])
		if err != nil {
			return
		}
	}
}
