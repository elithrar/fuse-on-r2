package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestListFilesHandlerBoundsDirectoryReads(t *testing.T) {
	mountPath := t.TempDir()
	for i := range maxEntries + 2 {
		name := filepath.Join(mountPath, fmt.Sprintf("file-%02d.txt", i))
		if err := os.WriteFile(name, []byte("data"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	t.Setenv("BUCKET_NAME", "example-bucket")
	t.Setenv("BUCKET_PREFIX", "assets")
	t.Setenv("MOUNT_PATH", mountPath)

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()
	rootHandler(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d: %s", response.Code, response.Body.String())
	}

	var body FileListResponse
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}

	if body.BucketName != "example-bucket" {
		t.Fatalf("expected bucket name example-bucket, got %q", body.BucketName)
	}
	if body.Prefix != "assets" {
		t.Fatalf("expected prefix assets, got %q", body.Prefix)
	}
	if body.MountPath != mountPath {
		t.Fatalf("expected mount path %q, got %q", mountPath, body.MountPath)
	}
	if body.Returned != maxEntries || len(body.Files) != maxEntries {
		t.Fatalf("expected %d files, got returned=%d len=%d", maxEntries, body.Returned, len(body.Files))
	}
	if !body.Truncated {
		t.Fatal("expected response to be truncated")
	}

	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(encoded, &fields); err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"bucketName", "mountPath", "returned", "truncated"} {
		if _, ok := fields[field]; !ok {
			t.Fatalf("expected camelCase JSON field %q", field)
		}
	}
}

func TestRootHandlerRejectsUnsupportedRequests(t *testing.T) {
	tests := []struct {
		name   string
		method string
		path   string
		status int
	}{
		{name: "unknown path", method: http.MethodGet, path: "/missing", status: http.StatusNotFound},
		{name: "unsupported method", method: http.MethodPost, path: "/", status: http.StatusMethodNotAllowed},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(test.method, test.path, nil)
			response := httptest.NewRecorder()
			rootHandler(response, request)

			if response.Code != test.status {
				t.Fatalf("expected status %d, got %d", test.status, response.Code)
			}
			if response.Header().Get("Content-Type") != "application/json; charset=utf-8" {
				t.Fatalf("expected JSON content type, got %q", response.Header().Get("Content-Type"))
			}
		})
	}
}

func TestHealthHandler(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()
	healthHandler(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "ok\n" {
		t.Fatalf("expected health response, got %q", response.Body.String())
	}
}
