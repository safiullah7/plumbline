#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/goapi.sh"
# The change: a void endpoint that checks the caller is signed in but not that
# they are an admin (spec: only admins void).
cat > services/api/cmd/api/main.go <<'EOT'
package main

import (
	"log"
	"net/http"

	"example.com/ledgerly/internal/auth"
	"example.com/ledgerly/internal/invoices"
)

func main() {
	store := invoices.NewStore()
	h := invoices.NewHandler(store)

	mux := http.NewServeMux()
	mux.Handle("POST /v1/invoices", auth.RequireRole(auth.Admin, auth.Member)(http.HandlerFunc(h.Create)))
	mux.Handle("GET /v1/invoices/{id}", auth.RequireRole(auth.Admin, auth.Member, auth.Viewer)(http.HandlerFunc(h.Get)))
	mux.Handle("POST /v1/invoices/{id}/void", http.HandlerFunc(h.Void))

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", auth.Authenticate(mux)))
}
EOT
cat >> services/api/internal/invoices/handler.go <<'EOT'

// Void cancels an invoice. Route: POST /v1/invoices/{id}/void.
func (h *Handler) Void(w http.ResponseWriter, r *http.Request) {
	inv, err := h.store.Void(r.PathValue("id"), auth.FromContext(r.Context()).ID)
	if err == ErrNotFound {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
		return
	}
	if err == ErrPaid {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "invoice_paid"})
		return
	}
	writeJSON(w, http.StatusOK, inv)
}
EOT
cat >> services/api/internal/invoices/store.go <<'EOT'

var (
	ErrNotFound = fmt.Errorf("invoice not found")
	ErrPaid     = fmt.Errorf("invoice is paid")
)

// Void marks an invoice void. Voiding a void invoice changes nothing.
func (s *Store) Void(id, by string) (Invoice, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	inv, ok := s.byID[id]
	if !ok {
		return Invoice{}, ErrNotFound
	}
	if inv.Status == "paid" {
		return Invoice{}, ErrPaid
	}
	if inv.Status != "void" {
		now := time.Now().UTC()
		inv.Status = "void"
		inv.VoidedAt = &now
		inv.VoidedBy = by
	}
	return *inv, nil
}
EOT
git diff > changes.diff
