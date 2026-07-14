package search

import (
	"strings"
)

func Normalize(s string) string {
	return strings.ToLower(
		strings.TrimSpace(s),
	)
}

func Contains(text string, query string) bool {

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

func MatchScore(value string, query string) int {
	value = Normalize(value)
	query = Normalize(query)

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

