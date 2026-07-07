package main

import (
	"encoding/json"
	"net/http"
	"strings"
)

type Event struct {
	EventID         string   `json:"event_id"`
	Timestamp       string   `json:"timestamp"`
	UserID          string   `json:"user_id"`
	MachineID       string   `json:"machine_id"`
	Action          string   `json:"action"`
	Channel         string   `json:"channel"`
	FileName        string   `json:"file_name"`
	FileExt         string   `json:"file_ext"`
	ContentClasses  []string `json:"content_classes"`
	DestinationType string   `json:"destination_type"`
	Destination     string   `json:"destination"`
	Severity        string   `json:"severity"`
}

var events []Event

type SearchRequest struct {
	User string `json:"user"`
}

type SearchResult struct {
	Event Event   `json:"event"`
}

func main() {
	events = append(events, Event{
		EventID:         "evt_12345",
		Timestamp:       "2026-06-16T10:15:00Z",
		UserID:          "ivanov",
		MachineID:       "pc_003",
		Action:          "email_send",
		Channel:         "email",
		FileName:        "client_base.xlsx",
		FileExt:         "xlsx",
		ContentClasses:  []string{"client_data", "personal_data"},
		DestinationType: "external",
		Destination:     "external_email_001",
		Severity:        "high",
	})
	events = append(events, Event{
		EventID:         "evt_12346",
		Timestamp:       "2026-06-16T10:15:00Z",
		UserID:          "ivrn0vjjjju",
		MachineID:       "pc_003",
		Action:          "email_send",
		Channel:         "email",
		FileName:        "client_base.xlsx",
		FileExt:         "xlsx",
		ContentClasses:  []string{"client_data", "personal_data"},
		DestinationType: "external",
		Destination:     "external_email_001",
		Severity:        "high",
	})

	http.HandleFunc("/search", searchHandler)

	if err := http.ListenAndServe(":8080", nil); err != nil {
		panic(err)
	}
}

func searchHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	var req SearchRequest

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	user := strings.ToLower(strings.TrimSpace(req.User))
	var result []SearchResult

	for _, event := range events {
		lowerUserID := strings.ToLower(event.UserID)
		if strings.Contains(lowerUserID, user) {
			
			result = append(result, SearchResult{
				Event: event,
			})
		}
	}

	if result == nil {
		result = []SearchResult{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
