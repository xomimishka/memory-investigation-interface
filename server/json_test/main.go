package main

import (
	"encoding/json"
	"fmt"
	"log"
)

func main() {
	//withoutTags()
	//withTags()
	unknownJson()
}

func withoutTags() {
	person := Person{
		name:    "John Doe",
		Age:     30,
		Married: true,
		Hobbies: []string{"reading", "traveling", "coding"},
		Address: Address{
			Country: "USA",
			City:    "New York",
		},
	}

	bytes, err := json.Marshal(person) // Преобразование структуры в JSON
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(string(bytes))

	var resultPerson Person
	err = json.Unmarshal(bytes, &resultPerson) // Преобразование JSON обратно в структуру
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(resultPerson)
}

func withTags() {
	person := PersonWithTags{
		Name:    "Jane Doe",
		Age:     28,
		Married: false,
		Hobbies: nil,
		Address: Address{
			Country: "Canada",
			City:    "Toronto",
		},
	}

	bytes, err := json.Marshal(person) // Преобразование структуры в JSON
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(string(bytes))

	var resultPerson PersonWithTags
	err = json.Unmarshal(bytes, &resultPerson) // Преобразование JSON обратно в структуру
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(resultPerson)
}

func unknownJson() {
	request := `{"first":1, "second":[2, 3]}`

	result := make(map[string]any) // result — пустая, но готовая к использованию карта

	if err := json.Unmarshal([]byte(request), &result); err != nil {
		log.Fatal(err)
	}

	for k, v := range result {
		fmt.Printf("Ключ: %s, Значение: %v \n", k, v)
	}
}