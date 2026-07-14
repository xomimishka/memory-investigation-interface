package datasets

import (
	"bufio"
	"encoding/json"
	"log"
	"os"

	"event-memory-search-api/internal/domain"
)

func LoadEvents(path string) []domain.Event {
	file, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	var events []domain.Event

	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		var event domain.Event

		if err := json.Unmarshal(scanner.Bytes(), &event); err == nil {
			events = append(events, event)
		}
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}

	return events
}