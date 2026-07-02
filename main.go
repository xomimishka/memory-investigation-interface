package main

import (
	"fmt"
	"math"
)

func main() {
	IMT := calculateIMT(getUserInput())
	outputresult(IMT)
}

func outputresult(imt float64) {
	result := fmt.Sprintf("Ваш индекс массы тела: %.0f", imt)
	fmt.Print(result)
}

func calculateIMT(USERkG float64, USERheight float64) float64 {
	const IMTPower = 2
	return USERkG / math.Pow(USERheight / 100, IMTPower)
}

func getUserInput() (float64, float64) {
	var height, kg float64
	fmt.Println("Калькулятор индекса тела")
	fmt.Print("Введите рост в сантиметрах: ")
	fmt.Scan(&height)
	fmt.Print("Введите вес в килограммах: ")
	fmt.Scan(&kg)
	return kg, height
}