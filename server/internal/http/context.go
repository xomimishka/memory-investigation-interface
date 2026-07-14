package http

import (
	"encoding/json"
	"net/http"
	"strings"

	"event-memory-search-api/internal/domain"
)

func (s *Server) ContextHandler(w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodGet {
		http.Error(
			w,
			"method not allowed",
			http.StatusMethodNotAllowed,
		)
		return
	}


	// /api/events/{event_id}/context

	id := strings.TrimPrefix(
		r.URL.Path,
		"/api/events/",
	)


	event, ok := s.Events[id]

	if !ok {
		http.Error(
			w,
			"event not found",
			http.StatusNotFound,
		)
		return
	}


	response := domain.EventContext{
		Event: event,
	}


	w.Header().Set(
		"Content-Type",
		"application/json",
	)


	json.NewEncoder(w).Encode(response)
}