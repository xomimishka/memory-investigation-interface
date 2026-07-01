package main

import (
	"fmt"
	"math"
)

func main() {
	const IMTPower = 2
	var height, kg float64
	fmt.Print("Калькулятор индекса тела \n")
	fmt.Print("Введите рост в метрах: ")
	fmt.Scan(&height)
	fmt.Print("Введите вес в килограммах: ")
	fmt.Scan(&kg)
	IMT := kg / math.Pow(height, IMTPower)
	fmt.Print("Ваш индекс массы тела: ", IMT)
}
