package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sort"
	"strings"
)

var datasets = map[string][]Event{}

func main() {
	datasets["control"] = loadEvents("events.jsonl")

	http.HandleFunc("/api/health", healthHandler)
	http.HandleFunc("/api/datasets", datasetsHandler)
	http.HandleFunc("/api/search", searchHandler)

	err := http.ListenAndServe(":8080", nil)

	if err != nil {
		log.Fatal(err)
	}
}

func cors(w http.ResponseWriter) {
	w.Header().Set(
		"Access-Control-Allow-Origin",
		"*",
	)

	w.Header().Set(
		"Access-Control-Allow-Headers",
		"Content-Type",
	)

	w.Header().Set(
		"Access-Control-Allow-Methods",
		"POST, OPTIONS",
	)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(
		map[string]string{
			"status": "ok",
		},
	)
}

func datasetsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	names := make([]string, 0)

	for name := range datasets {
		names = append(names, name)
	}

	json.NewEncoder(w).Encode(names)
}

func normalize(s string) string {
	return strings.ToLower(
		strings.TrimSpace(s),
	)
}

func contains(text string, query string) bool {

	text = strings.ToLower(
		strings.TrimSpace(text),
	)
	query = strings.ToLower(
		strings.TrimSpace(query),
	)
	if query == "" {
		return false
	}
	return strings.Contains(
		text,
		query,
	)
}

func matchScore(value string, query string) int {
	value = normalize(value)
	query = normalize(query)

	if query == "" {
		return 0
	}
	if value == query {
		return 50
	}
	if strings.HasPrefix(value, query) {
		return 40
	}
	if strings.Contains(value, query) {
		return 20
	}
	return 0
}

func searchHandler(w http.ResponseWriter, r *http.Request) {
	cors(w)

	if r.Method == http.MethodOptions {
		return
	}
	w.Header().Set("Content-Type", "application/json")

	var req SearchRequest

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(
			w,
			"bad json",
			http.StatusBadRequest,
		)
		return
	}

	events, ok := datasets[req.DatasetID]

	if !ok {
		http.Error(
			w,
			"dataset not found",
			http.StatusNotFound,
		)
		return
	}

	results := make([]SearchResult, 0)

	for _, event := range events {
		score := 0

		matched := make([]string, 0)

		userScore := matchScore(
			event.UserID,
			req.Hints.UserID,
		)

		if userScore > 0 {
			score += userScore

			matched = append(
				matched,
				"user_id",
			)
		}

		fileScore := matchScore(
			event.FileName,
			req.Hints.FileName,
		)

		if fileScore > 0 {
			score += fileScore

			matched = append(
				matched,
				"file_name",
			)
		}

		actionScore := matchScore(
			event.Action,
			req.Hints.Action,
		)

		if actionScore > 0 {
			score += actionScore

			matched = append(
				matched,
				"action",
			)
		}

		if req.Hints.DestinationType != "" {
			if strings.EqualFold(
				event.DestinationType,
				req.Hints.DestinationType,
			) {

				score += 20

				matched = append(
					matched,
					"destination_type",
				)
			}
		}

		if score > 0 {
			results = append(
				results,
				SearchResult{
					Score: score,
					MatchedHints: matched,
					Event: event,
				},
			)
		}
	}

	//сначала самые подходящие
	sort.Slice(
		results,
		func(i, j int) bool {

			return results[i].Score > results[j].Score

		},
	)
	resp := SearchResponse{
		Status: "done",
		DatasetID: req.DatasetID,
		TotalCandidates: len(results),
		Candidates: results,
	}
	json.NewEncoder(w).Encode(resp)
}