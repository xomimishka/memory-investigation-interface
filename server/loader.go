package main

import (
	"bufio"
	"encoding/json"
	"os"
	"log"
)

func loadEvents(path string) []Event {
	file, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	var events []Event

	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		var event Event

		if json.Unmarshal(scanner.Bytes(), &event) == nil {
			events = append(events, event)
		}
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}
	return events
}