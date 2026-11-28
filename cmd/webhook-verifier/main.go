package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	// DefaultMaxBodyBytes caps incoming webhook payloads at 1 MiB to prevent memory-exhaustion DoS.
	DefaultMaxBodyBytes int64 = 1 << 20
	signatureHeader           = "X-Hub-Signature-256"
	signaturePrefix           = "sha256="
)

// VerifierConfig holds runtime configuration for the HMAC-SHA256 webhook proxy.
type VerifierConfig struct {
	Secret       []byte
	UpstreamURL  string
	ListenAddr   string
	MaxBodyBytes int64
	HTTPClient   *http.Client
}

// VerifyHMACSignature validates a GitHub X-Hub-Signature-256 header against payload bytes in constant time.
func VerifyHMACSignature(payload []byte, sigHeader string, secret []byte) bool {
	if len(secret) == 0 || !strings.HasPrefix(sigHeader, signaturePrefix) {
		return false
	}
	sigHex := strings.TrimPrefix(sigHeader, signaturePrefix)
	sigBytes, err := hex.DecodeString(sigHex)
	if err != nil || len(sigBytes) != sha256.Size {
		return false
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write(payload)
	expected := mac.Sum(nil)
	return hmac.Equal(sigBytes, expected)
}

// NewWebhookHandler returns an http.Handler that enforces POST, caps body size, verifies HMAC-SHA256,
// and proxies authenticated webhook events to the internal CI server.
func NewWebhookHandler(cfg VerifierConfig) http.Handler {
	maxBytes := cfg.MaxBodyBytes
	if maxBytes <= 0 {
		maxBytes = DefaultMaxBodyBytes
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{
			Timeout: 10 * time.Second,
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	mux.HandleFunc("/hook", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		defer r.Body.Close()

		body, err := io.ReadAll(r.Body)
		if err != nil {
			var maxBytesErr *http.MaxBytesError
			if errors.As(err, &maxBytesErr) {
				http.Error(w, "Payload Too Large", http.StatusRequestEntityTooLarge)
				return
			}
			http.Error(w, "Bad Request", http.StatusBadRequest)
			return
		}

		sig := r.Header.Get(signatureHeader)
		if !VerifyHMACSignature(body, sig, cfg.Secret) {
			log.Printf("[SECURITY] Rejected webhook with invalid or missing HMAC signature from %s", r.RemoteAddr)
			http.Error(w, "Forbidden: Invalid HMAC signature", http.StatusForbidden)
			return
		}

		req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, cfg.UpstreamURL, bytes.NewReader(body))
		if err != nil {
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}

		// Forward relevant GitHub delivery headers to Woodpecker CI
		for _, hdr := range []string{"Content-Type", "X-GitHub-Event", "X-GitHub-Delivery", "X-GitHub-Hook-ID", signatureHeader} {
			if val := r.Header.Get(hdr); val != "" {
				req.Header.Set(hdr, val)
			}
		}

		resp, err := client.Do(req)
		if err != nil {
			log.Printf("[ERROR] Upstream CI proxy error: %v", err)
			http.Error(w, "Bad Gateway", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		w.WriteHeader(resp.StatusCode)
		_, _ = io.Copy(w, io.LimitReader(resp.Body, maxBytes))
	})

	return mux
}

func main() {
	secret := os.Getenv("GITHUB_WEBHOOK_SECRET")
	if len(secret) == 0 {
		log.Fatal("FATAL: GITHUB_WEBHOOK_SECRET environment variable must be set")
	}

	upstream := os.Getenv("WEBHOOK_UPSTREAM_URL")
	if upstream == "" {
		upstream = "http://127.0.0.1:8000/hook"
	}

	listenAddr := os.Getenv("WEBHOOK_LISTEN_ADDR")
	if listenAddr == "" {
		listenAddr = "127.0.0.1:9900"
	}

	cfg := VerifierConfig{
		Secret:       []byte(secret),
		UpstreamURL:  upstream,
		ListenAddr:   listenAddr,
		MaxBodyBytes: DefaultMaxBodyBytes,
	}

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           NewWebhookHandler(cfg),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("Starting hardened HMAC-SHA256 webhook verifier on %s -> %s", cfg.ListenAddr, cfg.UpstreamURL)
	log.Fatal(srv.ListenAndServe())
}
