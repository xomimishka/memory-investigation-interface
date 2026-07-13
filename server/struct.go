package main

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
	DatasetID string `json:"dataset_id"`

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
	DatasetID       string         `json:"dataset_id"`
	TotalCandidates int            `json:"total_candidates"`
	Candidates      []SearchResult `json:"candidates"`
}