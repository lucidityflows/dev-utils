package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"log"
	"net/http"
	"os"
)

var (
	secret    = []byte(os.Getenv("GITHUB_WEBHOOK_SECRET"))
	upstream  = "http://localhost:8000/hook/github"
)

func verifySignature(body []byte, sigHeader string) bool {
	if len(sigHeader) < 7 || sigHeader[:7] != "sha256=" {
		return false
	}
	sig, err := hex.DecodeString(sigHeader[7:])
	if err != nil {
		return false
	}
	h := hmac.New(sha256.New, secret)
	h.Write(body)
	return hmac.Equal(sig, h.Sum(nil))
}

func webhookHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	sig := r.Header.Get("X-Hub-Signature-256")
	if sig == "" {
		http.Error(w, "Missing signature", http.StatusUnauthorized)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("ERR: %v", err)
		http.Error(w, "Read error", http.StatusInternalServerError)
		return
	}
	r.Body.Close()

	if !verifySignature(body, sig) {
		log.Printf("Invalid signature from %s", r.RemoteAddr)
		http.Error(w, "Invalid signature", http.StatusForbidden)
		return
	}

	req, err := http.NewRequest("POST", upstream, io.NopCloser(io.NewSectionReader(io.NewBytesReader(body), 0, int64(len(body)))))
	if err != nil {
		http.Error(w, "Upstream error", http.StatusBadGateway)
		return
	}

	req.Header = r.Header.Clone()
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("Forwarding error: %v", err)
		http.Error(w, "Upstream error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func main() {
	if len(secret) == 0 {
		log.Fatal("GITHUB_WEBHOOK_SECRET env var is empty")
	}
	http.HandleFunc("/hook", webhookHandler)
	log.Println("Starting hardened webhook listener on :9900")
	log.Fatal(http.ListenAndServe(":9900", nil))
}
