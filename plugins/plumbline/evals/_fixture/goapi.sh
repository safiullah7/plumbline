#!/usr/bin/env bash
# Shared eval fixture for v0.4b: Ledgerly, a small Go invoices API for one
# company's finance team (surface api, single tenant, roles admin, member and
# viewer). Module "invoices" with one planned feature, 01-void-invoices: spec,
# acceptance criteria and a contract written, no code for it yet. Sourcing this
# file leaves one commit on main. Cases add what they test; $F is the feature
# folder, $G the Go service folder:
#   source "$(dirname "$0")/../_fixture/goapi.sh"
set -e
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false
G=services/api
mkdir -p "$G/cmd/api" "$G/internal/auth" "$G/internal/invoices"

project_profile no none "| api | Go | services/api/** | go -C services/api run ./cmd/api (http://localhost:8080) | go -C services/api vet ./... | cd services/api && golangci-lint run | go --dir services/api |"

new_feature invoices void-invoices standard api --no-ux
F=$FEATURE

cat > docs/product/invoices/vision.md <<'EOT'
# Invoices vision

Owner: product engineer

## Who it's for
The finance team of one company: admins who run billing, members who raise
invoices, and viewers (auditors, managers) who only read.

## Problem
Invoices are raised in a spreadsheet, so mistakes are fixed by overwriting rows
and nobody can say who changed what.

## Product principles
- An invoice is never edited or deleted after it is sent; it is voided.
- Every write names who did it.
- The API is the product: other tools in the company call it.

## Features
Each feature is named by the outcome it changes for a user. Folder:
docs/product/invoices/. Create and read invoices shipped before Plumbline.
| Feature | Goal | Outcome (measurable) | Why next | Status |
| --- | --- | --- | --- | --- |
| 01-void-invoices | Admins correct mistakes by voiding an invoice | 0 invoices overwritten in place | Overwrites are the audit team's top finding | Planned |
EOT

cat > "$F/spec.md" <<'EOT'
# Feature 01: Void invoices

Owner: product engineer

## Goal
An admin can void an invoice that was raised by mistake, so the record stays and
shows it was cancelled, instead of being overwritten.

## Requirements
| Priority | Requirement | Use case |
| --- | --- | --- |
| P0 | `POST /v1/invoices/{id}/void` voids a draft or sent invoice and returns it | UC-01-01 |
| P0 | A paid invoice cannot be voided | UC-01-01 |
| P0 | Only admins can void | UC-01-01 |
| P1 | Voiding an already voided invoice returns the same result | UC-01-01 |

## Business rules
- Statuses: draft, sent, paid, void. Only draft and sent invoices can be voided.
- A voided invoice keeps its number and amounts; `voided_at` and `voided_by` are set.

## Data and permissions
Roles: admin, member, viewer. Only admin may void. The caller is identified by
the bearer token; a request without a valid token is rejected before anything else.

## Non-Goals
Refunds, credit notes and un-voiding.

## Success metrics
| Metric | Target | Measured how, over what window |
| --- | --- | --- |
| Invoices overwritten in place | 0 | Audit log review, first quarter |
EOT

cat > "$F/acceptance-criteria.md" <<'EOT'
# Feature 01 acceptance criteria

Owner: product engineer. Every criterion is observable in the API and states the
exact expected result. Tests are named after these IDs. Priority matches the
requirement's priority in spec.md (P0, P1, P2).

| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | an admin and a draft invoice | the admin sends POST /v1/invoices/{id}/void | 200 and the body has status "void", voided_at and voided_by | P0 |
| AC-01-002 | UC-01-01 | an admin and a paid invoice | the admin sends POST /v1/invoices/{id}/void | 409 with {"error":"invoice_paid"} and the invoice is unchanged | P0 |
| AC-01-003 | UC-01-01 | a member and a draft invoice | the member sends POST /v1/invoices/{id}/void | 403 with {"error":"forbidden"} and the invoice is unchanged | P0 |
| AC-01-004 | UC-01-01 | a viewer | the viewer sends POST /v1/invoices/{id}/void | 403 with {"error":"forbidden"} | P0 |
| AC-01-005 | UC-01-01 | no token, or an expired one | POST /v1/invoices/{id}/void | 401 with {"error":"unauthenticated"} | P0 |
| AC-01-006 | UC-01-01 | an admin | they void an id that does not exist | 404 with {"error":"not_found"} | P0 |
| AC-01-007 | UC-01-01 | an invoice already voided | the admin voids it again | 200 and the same body, voided_at unchanged | P1 |
EOT

cat > "$F/contracts/void-invoice.md" <<'EOT'
# POST /v1/invoices/{id}/void

Auth: bearer token; role admin.

Response 200: Invoice
```json
{ "id": "inv_123", "status": "void", "amount_cents": 12000, "currency": "EUR",
  "voided_at": "2026-10-01T09:30:00Z", "voided_by": "u_7" }
```
Errors: 401 unauthenticated, 403 forbidden, 404 not_found, 409 invoice_paid.
Error body: `{ "error": "<code>" }`.
EOT

# The test plan is still the standard template, without the API evidence plan the
# surface overlay adds: the QA engineer plans the evidence from its By surface table.
sed 's/<phase>/01/g' "$FIXTURE_TEMPLATES/standard/test-plan.md" > "$F/test-plan.md"

cat > "$G/go.mod" <<'EOT'
module example.com/ledgerly

go 1.22
EOT

cat > "$G/cmd/api/main.go" <<'EOT'
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

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", auth.Authenticate(mux)))
}
EOT

cat > "$G/internal/auth/auth.go" <<'EOT'
// Package auth identifies the caller from a bearer token and checks their role.
package auth

import (
	"context"
	"net/http"
	"strings"
)

type Role string

const (
	Admin  Role = "admin"
	Member Role = "member"
	Viewer Role = "viewer"
)

type User struct {
	ID   string
	Role Role
}

type ctxKey struct{}

// tokens stands in for the real token service in the demo.
var tokens = map[string]User{
	"admin-token":  {ID: "u_1", Role: Admin},
	"member-token": {ID: "u_2", Role: Member},
	"viewer-token": {ID: "u_3", Role: Viewer},
}

// Authenticate rejects requests without a valid bearer token with 401.
func Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		user, ok := tokens[token]
		if !ok {
			http.Error(w, `{"error":"unauthenticated"}`, http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, user)))
	})
}

// RequireRole allows only the listed roles; everyone else gets 403.
func RequireRole(roles ...Role) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			user, _ := r.Context().Value(ctxKey{}).(User)
			for _, role := range roles {
				if user.Role == role {
					next.ServeHTTP(w, r)
					return
				}
			}
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		})
	}
}

// FromContext returns the authenticated user.
func FromContext(ctx context.Context) User {
	user, _ := ctx.Value(ctxKey{}).(User)
	return user
}
EOT

cat > "$G/internal/invoices/store.go" <<'EOT'
package invoices

import (
	"fmt"
	"sync"
	"time"
)

type Invoice struct {
	ID          string     `json:"id"`
	Status      string     `json:"status"` // draft, sent, paid, void
	AmountCents int64      `json:"amount_cents"`
	Currency    string     `json:"currency"`
	Customer    string     `json:"customer"`
	CreatedBy   string     `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
	VoidedAt    *time.Time `json:"voided_at,omitempty"`
	VoidedBy    string     `json:"voided_by,omitempty"`
}

// Store keeps invoices in memory.
type Store struct {
	mu   sync.Mutex
	next int
	byID map[string]*Invoice
}

func NewStore() *Store { return &Store{next: 1, byID: map[string]*Invoice{}} }

func (s *Store) Create(inv Invoice) Invoice {
	s.mu.Lock()
	defer s.mu.Unlock()
	inv.ID = fmt.Sprintf("inv_%d", s.next)
	s.next++
	inv.Status = "draft"
	inv.CreatedAt = time.Now().UTC()
	s.byID[inv.ID] = &inv
	return inv
}

func (s *Store) Get(id string) (Invoice, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	inv, ok := s.byID[id]
	if !ok {
		return Invoice{}, false
	}
	return *inv, true
}
EOT

cat > "$G/internal/invoices/handler.go" <<'EOT'
package invoices

import (
	"encoding/json"
	"net/http"

	"example.com/ledgerly/internal/auth"
)

type Handler struct{ store *Store }

func NewHandler(s *Store) *Handler { return &Handler{store: s} }

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// Create raises a draft invoice. Routes: POST /v1/invoices (admin, member).
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var in struct {
		AmountCents int64  `json:"amount_cents"`
		Currency    string `json:"currency"`
		Customer    string `json:"customer"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad_request"})
		return
	}
	if in.AmountCents <= 0 || in.Customer == "" {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "invalid_invoice"})
		return
	}
	inv := h.store.Create(Invoice{
		AmountCents: in.AmountCents,
		Currency:    in.Currency,
		Customer:    in.Customer,
		CreatedBy:   auth.FromContext(r.Context()).ID,
	})
	writeJSON(w, http.StatusCreated, inv)
}

// Get returns one invoice. Route: GET /v1/invoices/{id} (any role).
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	inv, ok := h.store.Get(r.PathValue("id"))
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
		return
	}
	writeJSON(w, http.StatusOK, inv)
}
EOT

cat > "$G/internal/invoices/handler_test.go" <<'EOT'
package invoices

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"example.com/ledgerly/internal/auth"
)

func serve(h *Handler) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("POST /v1/invoices", auth.RequireRole(auth.Admin, auth.Member)(http.HandlerFunc(h.Create)))
	mux.Handle("GET /v1/invoices/{id}", auth.RequireRole(auth.Admin, auth.Member, auth.Viewer)(http.HandlerFunc(h.Get)))
	return auth.Authenticate(mux)
}

func do(srv http.Handler, method, path, token, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	return rec
}

func TestCreateInvoice(t *testing.T) {
	srv := serve(NewHandler(NewStore()))
	rec := do(srv, "POST", "/v1/invoices", "member-token", `{"amount_cents":12000,"currency":"EUR","customer":"Acme"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("got %d, want 201", rec.Code)
	}
}

func TestCreateInvoiceRejectsViewer(t *testing.T) {
	srv := serve(NewHandler(NewStore()))
	rec := do(srv, "POST", "/v1/invoices", "viewer-token", `{"amount_cents":12000,"currency":"EUR","customer":"Acme"}`)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("got %d, want 403", rec.Code)
	}
}

func TestGetInvoiceNotFound(t *testing.T) {
	srv := serve(NewHandler(NewStore()))
	rec := do(srv, "GET", "/v1/invoices/inv_404", "viewer-token", "")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("got %d, want 404", rec.Code)
	}
}
EOT

git add -A
git commit -qm "Ledgerly API with the planned void-invoices feature"
