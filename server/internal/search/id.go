package search

import (
    "fmt"
    "time"
)

func NewSearchID() string {
    return fmt.Sprintf(
        "srch_%d",
        time.Now().UnixNano(),
    )
}