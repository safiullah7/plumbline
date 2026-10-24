#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/goapi.sh"
# The change: GET /v1/invoices lists every invoice for any signed-in role. The
# profile says Multi-tenant: no, so listing everything is correct.
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
	mux.Handle("GET /v1/invoices", auth.RequireRole(auth.Admin, auth.Member, auth.Viewer)(http.HandlerFunc(h.List)))
	mux.Handle("GET /v1/invoices/{id}", auth.RequireRole(auth.Admin, auth.Member, auth.Viewer)(http.HandlerFunc(h.Get)))

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", auth.Authenticate(mux)))
}
EOT
cat >> services/api/internal/invoices/handler.go <<'EOT'

// List returns every invoice. Route: GET /v1/invoices (any role).
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.store.List())
}
EOT
cat >> services/api/internal/invoices/store.go <<'EOT'

// List returns all invoices.
func (s *Store) List() []Invoice {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Invoice, 0, len(s.byID))
	for _, inv := range s.byID {
		out = append(out, *inv)
	}
	return out
}
EOT
git diff > changes.diff
