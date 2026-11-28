package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func signPayload(payload []byte, secret []byte) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write(payload)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func TestVerifyHMACSignature(t *testing.T) {
	secret := []byte("test-super-secret-webhook-key")
	payload := []byte(`{"action":"opened","number":42}`)
	validSig := signPayload(payload, secret)

	if !VerifyHMACSignature(payload, validSig, secret) {
		t.Fatalf("expected valid signature to pass verification")
	}

	if VerifyHMACSignature(payload, validSig, []byte("wrong-secret")) {
		t.Fatalf("expected signature with wrong secret to fail")
	}

	if VerifyHMACSignature([]byte(`{"action":"tampered"}`), validSig, secret) {
		t.Fatalf("expected tampered payload to fail verification")
	}

	if VerifyHMACSignature(payload, "sha1=deadbeef", secret) {
		t.Fatalf("expected non-sha256 prefix to fail")
	}

	if VerifyHMACSignature(payload, "sha256=not-hex", secret) {
		t.Fatalf("expected malformed hex to fail")
	}
}

func TestWebhookHandler_EndToEnd(t *testing.T) {
	secret := []byte("unit-test-hmac-secret-key")
	var forwardedBody []byte
	var forwardedEvent string

	upstreamServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		forwardedEvent = r.Header.Get("X-GitHub-Event")
		forwardedBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"queued":true}`))
	}))
	defer upstreamServer.Close()

	handler := NewWebhookHandler(VerifierConfig{
		Secret:       secret,
		UpstreamURL:  upstreamServer.URL,
		MaxBodyBytes: 1024,
	})

	t.Run("rejects non-POST requests with 405", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/hook", nil)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected 405, got %d", rec.Code)
		}
	})

	t.Run("rejects unsigned requests with 403", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/hook", strings.NewReader(`{"ref":"refs/heads/main"}`))
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d", rec.Code)
		}
	})

	t.Run("rejects oversized payloads with 413", func(t *testing.T) {
		largePayload := bytes.Repeat([]byte("A"), 2048)
		req := httptest.NewRequest(http.MethodPost, "/hook", bytes.NewReader(largePayload))
		req.Header.Set("X-Hub-Signature-256", signPayload(largePayload, secret))
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Fatalf("expected 413, got %d", rec.Code)
		}
	})

	t.Run("forwards valid HMAC signed payload to upstream CI", func(t *testing.T) {
		payload := []byte(`{"ref":"refs/heads/main","repository":{"full_name":"lucidityflows/debian-ci-hardening"}}`)
		req := httptest.NewRequest(http.MethodPost, "/hook", bytes.NewReader(payload))
		req.Header.Set("X-Hub-Signature-256", signPayload(payload, secret))
		req.Header.Set("X-GitHub-Event", "push")

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusAccepted {
			t.Fatalf("expected 202 from upstream, got %d", rec.Code)
		}
		if forwardedEvent != "push" {
			t.Fatalf("expected X-GitHub-Event 'push' to be forwarded, got %q", forwardedEvent)
		}
		if !bytes.Equal(forwardedBody, payload) {
			t.Fatalf("forwarded body did not match original payload")
		}
	})

	t.Run("responds 200 OK on /healthz", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 on /healthz, got %d", rec.Code)
		}
	})
}
