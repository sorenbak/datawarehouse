package main

import (
	"fmt"
	"strconv"
	"time"

	"github.com/gobuffalo/envy"
)

var SLEEPSECS, _ = strconv.Atoi(envy.Get("SLEEPSECS", "60"))

func Daemon() {
	for true {
		fmt.Printf("Waited another [%d] secs", SLEEPSECS)
		time.Sleep(time.Duration(SLEEPSECS) * time.Second)
	}

}
