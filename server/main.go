package main

import (
	"github.com/agnivade/levenshtein"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"math"
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
	Score float64 `json:"score"`
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
	}

	e := echo.New()
	e.Use(middleware.CORS())
	e.POST("/search", searchHandler)
	e.Start("localhost:8080")
}

func searchHandler(c echo.Context) error {
	var req SearchRequest

	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, "bad request")
	}

	var result []SearchResult

	user := strings.ToLower(strings.TrimSpace(req.User))

	for _, event := range events {
		score := similarity(user, event.UserID)
		if strings.Contains(strings.ToLower(event.UserID), user) || score >= 60 {
			result = append(result, SearchResult{
				Event: event,
				Score: score,
			})
		}
	}

	return c.JSON(http.StatusOK, result)
}

func similarity(a, b string) float64 {
	a = strings.ToLower(strings.TrimSpace(a))
	b = strings.ToLower(strings.TrimSpace(b))

	distance := levenshtein.ComputeDistance(a, b)

	maxLen := len(a)
	if len(b) > maxLen {
		maxLen = len(b)
	}

	if maxLen == 0 {
		return 100
	}

	score := (1 - float64(distance)/float64(maxLen)) * 100
	return math.Round(score*10) / 10
}

// func main() {
// 	IMT := calculateIMT(getUserInput())
// 	outputresult(IMT)
// }

// func outputresult(imt float64) {
// 	result := fmt.Sprintf("Ваш индекс массы тела: %.0f", imt)
// 	fmt.Print(result)
// }

// func calculateIMT(USERkG float64, USERheight float64) float64 {
// 	const IMTPower = 2
// 	return USERkG / math.Pow(USERheight / 100, IMTPower)
// }

// func getUserInput() (float64, float64) {
// 	var height, kg float64
// 	fmt.Println("Калькулятор индекса тела")
// 	fmt.Print("Введите рост в сантиметрах: ")
// 	fmt.Scan(&height)
// 	fmt.Print("Введите вес в килограммах: ")
// 	fmt.Scan(&kg)
// 	return kg, height
// }

// import (
//     "fmt"
//     "net/http"
// 	"github.com/google/uuid"
//     "github.com/knetic/govaluate"
//     "github.com/labstack/echo/v4"
//     "github.com/labstack/echo/v4/middleware"
// )

// type Calculation struct {
// 	ID         string `json:"id"`
// 	Expression string `json:"expression"` // математическое выражение -например, 2+2
// 	Result     string `json:"result"` // 4
// }

// type CalculationRequest struct {
// 	Expression string `json:"expression"`
// }

// var calculations []Calculation

// func calculateExpression(expression string) (string, error) {
//     expr, err := govaluate.NewEvaluableExpression(expression)
//     if err != nil {
//         return "", err
//     }
//     result, err := expr.Evaluate(nil)
//     if err != nil {
//         return "", err
//     }
//     return fmt.Sprintf("%v", result), nil
// }

// func getCalculations(c echo.Context) error{
// 	return c.JSON(http.StatusOK, calculations)
// }

// func postCalculation(c echo.Context) error {
// 	var req CalculationRequest
// 	if err := c.Bind(&req); err != nil {
// 		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid request"})
// 	}
// 	result, err := calculateExpression(req.Expression)
// 	if err != nil {
// 		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid expression"})
// 	}
// 	calc := Calculation{
// 		ID:         uuid.NewString(),
// 		Expression: req.Expression,
// 		Result:     result,
// 	}
// 	calculations = append(calculations, calc)
// 	return c.JSON(http.StatusCreated, calc)
// }

// func main() {
// 	e := echo.New()
// 	e.Use(middleware.CORS())
// 	e.Use(middleware.Logger())

// 	e.GET("/calculations", getCalculations)
// 	e.POST("/calculations", postCalculation)
// 	e.Start("localhost:8080")
// }
