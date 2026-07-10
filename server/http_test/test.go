package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

type User struct {
	Name string `json:"name"`
	Age  int    `json:"age"`
}

func main() {

	http.HandleFunc("/hello", helloHandler)
	http.HandleFunc("/user", userHandler)

	fmt.Println("Server started on :8080")

	http.ListenAndServe(":8080", nil)
}

func helloHandler(w http.ResponseWriter, r *http.Request) {

	fmt.Println("METHOD:", r.Method)

	response := map[string]string{
		"message": "Hello!",
	}

	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(response)
}

func userHandler(w http.ResponseWriter, r *http.Request) {

	fmt.Println("METHOD:", r.Method)

	var user User

	json.NewDecoder(r.Body).Decode(&user)

	fmt.Println("Получили от React:")
	fmt.Println(user.Name)
	fmt.Println(user.Age)

	user.Age++

	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(user)
}