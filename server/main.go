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
	Hints struct {
		UserID          string `json:"user_id"`
		FileName        string `json:"file_name"`
		Action          string `json:"action"`
		DestinationType string `json:"destination_type"`
	} `json:"hints"`
}

type SearchResult struct {
	Score        int      `json:"score"`
	MatchedHints []string `json:"matched_hints"`
	Event        Event    `json:"event"`
}

type SearchResponse struct {
	Status          string         `json:"status"`
	TotalCandidates int            `json:"total_candidates"`
	Candidates      []SearchResult `json:"candidates"`
}

func main() {

	events = []Event{
		{
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
		},
		{
			EventID:         "evt_12346",
			Timestamp:       "2026-06-16T11:00:00Z",
			UserID:          "ivr",
			MachineID:       "pc_004",
			Action:          "file_copy",
			Channel:         "usb",
			FileName:        "salary.xlsx",
			FileExt:         "xlsx",
			ContentClasses:  []string{"finance"},
			DestinationType: "usb",
			Destination:     "Kingston",
			Severity:        "medium",
		},
		{
			EventID:         "evt_12347",
			Timestamp:       "2026-06-16T12:00:00Z",
			UserID:          "ivan.petrov",
			MachineID:       "pc_005",
			Action:          "email_send",
			Channel:         "email",
			FileName:        "client_list.xlsx",
			FileExt:         "xlsx",
			ContentClasses:  []string{"client_data"},
			DestinationType: "external",
			Destination:     "gmail",
			Severity:        "high",
		},
	}

	http.HandleFunc("/search", searchHandler)

	http.ListenAndServe(":8080", nil)
}

func searchHandler(w http.ResponseWriter, r *http.Request) {

	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")

	if r.Method == http.MethodOptions {
		return
	}

	var req SearchRequest

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}

	var results []SearchResult

	for _, event := range events {

		score := 0
		var matched []string

		if req.Hints.UserID != "" &&
			strings.Contains(
				strings.ToLower(event.UserID),
				strings.ToLower(req.Hints.UserID),
			) {

			score += 30
			matched = append(matched, "user_id")
		}

		if req.Hints.FileName != "" &&
			strings.Contains(
				strings.ToLower(event.FileName),
				strings.ToLower(req.Hints.FileName),
			) {

			score += 30
			matched = append(matched, "file_name")
		}

		if req.Hints.Action != "" &&
			strings.Contains(
				strings.ToLower(event.Action),
				strings.ToLower(req.Hints.Action),
			) {

			score += 20
			matched = append(matched, "action")
		}

		if req.Hints.DestinationType != "" &&
			strings.EqualFold(event.DestinationType, req.Hints.DestinationType) {

			score += 20
			matched = append(matched, "destination_type")
		}

		if score > 0 {
			results = append(results, SearchResult{
				Score:        score,
				MatchedHints: matched,
				Event:        event,
			})
		}
	}

	resp := SearchResponse{
		Status:          "done",
		TotalCandidates: len(results),
		Candidates:      results,
	}

	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(resp)
}