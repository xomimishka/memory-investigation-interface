package main

// import (
// 	"fmt"
// 	"math"
// )

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

import (
    "fmt"
    "net/http"
	"github.com/google/uuid"
    "github.com/knetic/govaluate"
    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"
)

type Calculation struct {
	ID         string `json:"id"`
	Expression string `json:"expression"` // математическое выражение -например, 2+2
	Result     string `json:"result"` // 4
}

type CalculationRequest struct {
	Expression string `json:"expression"`
}

var calculations []Calculation

func calculateExpression(expression string) (string, error) {
    expr, err := govaluate.NewEvaluableExpression(expression)
    if err != nil {
        return "", err
    }
    result, err := expr.Evaluate(nil)
    if err != nil {
        return "", err
    }
    return fmt.Sprintf("%v", result), nil
}

func getCalculations(c echo.Context) error{
	return c.JSON(http.StatusOK, calculations)
}

func postCalculation(c echo.Context) error {
	var req CalculationRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid request"})
	}
	result, err := calculateExpression(req.Expression)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid expression"})
	}
	calc := Calculation{
		ID:         uuid.NewString(),
		Expression: req.Expression,
		Result:     result,
	}
	calculations = append(calculations, calc)
	return c.JSON(http.StatusCreated, calc)
}

func main() {
	e := echo.New()
	e.Use(middleware.CORS())
	e.Use(middleware.Logger())

	e.GET("/calculations", getCalculations)
	e.POST("/calculations", postCalculation)
	e.Start("localhost:8080")
}
