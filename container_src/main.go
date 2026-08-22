package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const maxEntries = 10

type FileInfo struct {
	Name  string `json:"name"`
	IsDir bool   `json:"isDir"`
	Size  int64  `json:"size"`
}

type FileListResponse struct {
	BucketName string     `json:"bucketName"`
	Prefix     string     `json:"prefix"`
	MountPath  string     `json:"mountPath"`
	Files      []FileInfo `json:"files"`
	Returned   int        `json:"returned"`
	Truncated  bool       `json:"truncated"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	var body bytes.Buffer
	if err := json.NewEncoder(&body).Encode(value); err != nil {
		log.Printf("Failed to encode JSON response: %v", err)
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if _, err := w.Write(body.Bytes()); err != nil {
		log.Printf("Warning: failed to write response: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, ErrorResponse{Error: message})
}

func listFilesHandler(w http.ResponseWriter, _ *http.Request) {
	bucketName := os.Getenv("BUCKET_NAME")
	if bucketName == "" {
		writeError(w, http.StatusInternalServerError, "BUCKET_NAME environment variable not set")
		return
	}

	mountPath := os.Getenv("MOUNT_PATH")
	if mountPath == "" {
		writeError(w, http.StatusInternalServerError, "MOUNT_PATH environment variable not set")
		return
	}

	directory, err := os.Open(mountPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to open directory %s: %v", mountPath, err))
		return
	}
	defer func() {
		if err := directory.Close(); err != nil {
			log.Printf("Warning: failed to close %s: %v", mountPath, err)
		}
	}()

	entries, err := directory.ReadDir(maxEntries + 1)
	if err != nil && !errors.Is(err, io.EOF) {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to read directory %s: %v", mountPath, err))
		return
	}

	truncated := len(entries) > maxEntries
	if truncated {
		entries = entries[:maxEntries]
	}

	files := make([]FileInfo, 0, len(entries))
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			log.Printf("Warning: could not get info for %s: %v", entry.Name(), err)
			continue
		}

		files = append(files, FileInfo{
			Name:  entry.Name(),
			IsDir: entry.IsDir(),
			Size:  info.Size(),
		})
	}

	response := FileListResponse{
		BucketName: bucketName,
		Prefix:     os.Getenv("BUCKET_PREFIX"),
		MountPath:  mountPath,
		Files:      files,
		Returned:   len(files),
		Truncated:  truncated,
	}

	writeJSON(w, http.StatusOK, response)
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}

	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	listFilesHandler(w, r)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write([]byte("ok\n")); err != nil {
		log.Printf("Warning: failed to write health response: %v", err)
	}
}

func main() {
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	router := http.NewServeMux()
	router.HandleFunc("/", rootHandler)
	router.HandleFunc("/health", healthHandler)

	server := &http.Server{
		Addr:              ":8080",
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("Server listening on %s", server.Addr)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case sig := <-stop:
		log.Printf("Received signal (%s), shutting down server...", sig)
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Server failed: %v", err)
		}
		return
	}
	signal.Stop(stop)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatal(err)
	}

	log.Println("Server shutdown successfully")
}
