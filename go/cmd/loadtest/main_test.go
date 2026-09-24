package main

import "testing"

func TestParseStages(t *testing.T) {
	stages, err := parseStages("50, 250,500")
	if err != nil {
		t.Fatal(err)
	}
	if len(stages) != 3 || stages[0] != 50 || stages[2] != 500 {
		t.Fatalf("stages = %v", stages)
	}
}

func TestParseStagesRejectsInvalidValues(t *testing.T) {
	for _, value := range []string{"", "0", "50,nope"} {
		if _, err := parseStages(value); err == nil {
			t.Fatalf("parseStages(%q) accepted invalid input", value)
		}
	}
}
