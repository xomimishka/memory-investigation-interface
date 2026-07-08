package main

type Person struct {// если поле с большой буквы, то оно экспортируемое и будет отображаться в JSON, если с маленькой, то не будет
	name string
	Age  int
	Married bool
	Hobbies []string
	Address Address
}

type Address struct {
	Country string
	City    string
}

type PersonWithTags struct {
	Name string `json:"name"`
	Age  int    `json:"age"`
	Married bool `json:"married"`
	Hobbies []string `json:"hobbies,omitempty"`// если поле пустое, то оно не будет отображаться в JSON
	Address Address `json:"-"`// если поле не нужно отображать в JSON, то можно использовать тег "-"
}

type CustomPerson struct {
	Name string
	Age  int
	Married bool
	Hobbies []string
	Address Address
}

