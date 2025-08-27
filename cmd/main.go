package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

type HealthResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
	Version   string    `json:"version"`
	Component string    `json:"component"`
}

type InfoResponse struct {
	Name        string    `json:"name"`
	Version     string    `json:"version"`
	Description string    `json:"description"`
	BuildTime   string    `json:"build_time"`
	GoVersion   string    `json:"go_version"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now(),
		Version:   getEnvOrDefault("APP_VERSION", "1.0.0"),
		Component: "tekton-slsa-demo",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func infoHandler(w http.ResponseWriter, r *http.Request) {
	response := InfoResponse{
		Name:        "Tekton SLSA Demo Application",
		Version:     getEnvOrDefault("APP_VERSION", "1.0.0"),
		Description: "A sample application demonstrating SLSA compliance with Tekton Chains",
		BuildTime:   getEnvOrDefault("BUILD_TIME", time.Now().Format(time.RFC3339)),
		GoVersion:   getEnvOrDefault("GO_VERSION", "unknown"),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html>
<head>
    <title>Tekton SLSA Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; }
        .endpoint { background: #ecf0f1; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .endpoint code { background: #34495e; color: white; padding: 5px 10px; border-radius: 3px; }
        .status { color: #27ae60; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Tekton SLSA Demo Application</h1>
        <p class="status">✅ Application is running successfully!</p>
        
        <h2>Available Endpoints:</h2>
        <div class="endpoint">
            <strong>Health Check:</strong> <code>GET /health</code>
            <p>Returns the application health status and metadata</p>
        </div>
        
        <div class="endpoint">
            <strong>Application Info:</strong> <code>GET /info</code>
            <p>Returns detailed application information and build metadata</p>
        </div>
        
        <h2>About This Demo</h2>
        <p>This application demonstrates SLSA (Supply-chain Levels for Software Artifacts) compliance using Tekton Chains. The build process generates cryptographically signed attestations that prove the integrity of the software supply chain.</p>
        
        <h3>SLSA Features Demonstrated:</h3>
        <ul>
            <li>Automated build processes with Tekton Pipelines</li>
            <li>Cryptographic signing of build artifacts</li>
            <li>Generation of SLSA provenance attestations</li>
            <li>Supply chain security verification</li>
        </ul>
        
        <p><em>Version: %s | Built with Tekton Chains</em></p>
    </div>
</body>
</html>`

	version := getEnvOrDefault("APP_VERSION", "1.0.0")
	w.Header().Set("Content-Type", "text/html")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, html, version)
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	port := getEnvOrDefault("PORT", "8080")

	http.HandleFunc("/", rootHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/info", infoHandler)

	log.Printf("Starting Tekton SLSA Demo server on port %s", port)
	log.Printf("Health endpoint: http://localhost:%s/health", port)
	log.Printf("Info endpoint: http://localhost:%s/info", port)
	
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}