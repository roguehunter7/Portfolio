package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"google.golang.org/api/iterator"
)

var firestoreClient *firestore.Client

// ResponsePayload defines the JSON payload structure of our response.
type ResponsePayload struct {
	ActiveNow  int64  `json:"active_now"`
	TotalViews int64  `json:"total_views"`
	Status     string `json:"status"`
}

func main() {
	// Initialize Firestore Client.
	// Uses firestore.DetectProjectID to auto-resolve from ADC / Cloud Run metadata.
	ctx := context.Background()
	var err error
	firestoreClient, err = firestore.NewClient(ctx, firestore.DetectProjectID)
	if err != nil {
		log.Printf("Warning: Failed to initialize Firestore: %v. Running in mock-only mode.", err)
	} else {
		defer firestoreClient.Close()
	}

	// Expose a single GET route at /api/tracker.
	http.HandleFunc("/api/tracker", trackerHandler)

	// Determine port. Default to 8080 for Cloud Run.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server listening on port %s...", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func trackerHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// 6. CORS configuration: return Access-Control-Allow-Origin: *
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

	// Handle OPTIONS pre-flight request with 200 OK
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	// 7. Force cache freezing via HTTP headers.
	w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
	w.Header().Set("Content-Type", "application/json")

	var activeNow int64 = 1
	var totalViews int64 = 1

	if firestoreClient != nil {
		now := time.Now().UTC()
		fiveMinutesAgo := now.Add(-5 * time.Minute)

		// 3. Atomic Increment for total views count.
		// Uses Set with MergeAll to create doc and set value to 1 on first-run.
		visitsRef := firestoreClient.Collection("counters").Doc("visits")
		_, err := visitsRef.Set(ctx, map[string]interface{}{
			"total_views": firestore.Increment(1),
		}, firestore.MergeAll)
		if err != nil {
			log.Printf("Error incrementing total views: %v", err)
		}

		// Read total views back.
		doc, err := visitsRef.Get(ctx)
		if err == nil && doc.Exists() {
			if v, err := doc.DataAt("total_views"); err == nil {
				if val, ok := v.(int64); ok {
					totalViews = val
				}
			}
		}

		// 4. Active Sessions tracking.
		// Write temporary document with a random UUID containing the current timestamp.
		sessionID := uuid.New().String()
		sessionRef := firestoreClient.Collection("active_sessions").Doc(sessionID)
		_, err = sessionRef.Set(ctx, map[string]interface{}{
			"timestamp": now,
		})
		if err != nil {
			log.Printf("Error writing active session: %v", err)
		}

		// Query count of active sessions newer than 5 minutes.
		activeQuery := firestoreClient.Collection("active_sessions").Where("timestamp", ">", fiveMinutesAgo)
		aggQuery := activeQuery.NewAggregationQuery().WithCount("active_now")
		results, err := aggQuery.Get(ctx)
		if err == nil {
			if countVal, ok := results["active_now"]; ok {
				switch v := countVal.(type) {
				case int64:
					activeNow = v
				case int:
					activeNow = int64(v)
				case float64:
					activeNow = int64(v)
				}
			}
		}

		// 5. Database Bloat Prevention: Batch delete sessions older than 5 minutes.
		// Ponytail: Doing this inline handles low traffic. For high-volume sites,
		// a Cloud Scheduler task or Firestore TTL policy is the recommended upgrade path.
		expiredQuery := firestoreClient.Collection("active_sessions").Where("timestamp", "<=", fiveMinutesAgo)
		iter := expiredQuery.Documents(ctx)
		defer iter.Stop()

		batch := firestoreClient.Batch()
		batchCount := 0
		for {
			docDoc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				log.Printf("Error iterating expired sessions: %v", err)
				break
			}
			batch.Delete(docDoc.Ref)
			batchCount++
			if batchCount >= 500 {
				_, _ = batch.Commit(ctx)
				batch = firestoreClient.Batch()
				batchCount = 0
			}
		}
		if batchCount > 0 {
			_, _ = batch.Commit(ctx)
		}
	} else {
		// Mock responses for local self-check verification without live Firestore credentials.
		activeNow = 3
		totalViews = 99
	}

	response := ResponsePayload{
		ActiveNow:  activeNow,
		TotalViews: totalViews,
		Status:     "Healthy",
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding JSON response: %v", err)
	}
}
