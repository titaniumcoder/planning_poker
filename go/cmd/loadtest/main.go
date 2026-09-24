package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/titaniumcoder/planning-poker/go/internal/loadtest"
)

type options struct {
	target       string
	stages       string
	usersMin     int
	usersMax     int
	roundsMin    int
	roundsMax    int
	delayMin     time.Duration
	delayMax     time.Duration
	roomRamp     time.Duration
	webSockets   bool
	seed         uint64
	stageTimeout time.Duration
	maxErrorRate float64
	maxP95       time.Duration
}

type output struct {
	Target  string            `json:"target"`
	Stages  []loadtest.Report `json:"stages"`
	Passed  bool              `json:"passed"`
	Failure string            `json:"failure,omitempty"`
}

func main() {
	os.Exit(run())
}

func run() int {
	cfg := parseFlags()
	stages, err := parseStages(cfg.stages)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	result := output{Target: cfg.target, Passed: true}
	for stageIndex, rooms := range stages {
		stageCtx, cancel := context.WithTimeout(context.Background(), cfg.stageTimeout)
		report, runErr := loadtest.Run(stageCtx, loadtest.Config{
			TargetURL: cfg.target, Rooms: rooms, UsersMin: cfg.usersMin, UsersMax: cfg.usersMax,
			RoundsMin: cfg.roundsMin, RoundsMax: cfg.roundsMax, DelayMin: cfg.delayMin,
			DelayMax: cfg.delayMax, RoomRamp: cfg.roomRamp, WebSockets: cfg.webSockets,
			Seed: cfg.seed + uint64(stageIndex),
		})
		cancel()
		result.Stages = append(result.Stages, report)
		if runErr != nil {
			result.Passed, result.Failure = false, runErr.Error()
			break
		}
		if report.RoomsSucceeded != report.RoomsRequested {
			result.Passed = false
			result.Failure = fmt.Sprintf(
				"stage %d completed %d of %d rooms", rooms, report.RoomsSucceeded, report.RoomsRequested,
			)
			break
		}
		if report.ErrorRate > cfg.maxErrorRate {
			result.Passed = false
			result.Failure = fmt.Sprintf(
				"stage %d error rate %.4f exceeded %.4f", rooms, report.ErrorRate, cfg.maxErrorRate,
			)
			break
		}
		if report.P95 > cfg.maxP95 {
			result.Passed = false
			result.Failure = fmt.Sprintf(
				"stage %d p95 %s exceeded %s", rooms, report.P95, cfg.maxP95,
			)
			break
		}
	}
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(result); err != nil {
		fmt.Fprintln(os.Stderr, "encode report:", err)
		return 2
	}
	if !result.Passed {
		return 1
	}
	return 0
}

func parseFlags() options {
	var cfg options
	flag.StringVar(&cfg.target, "target", "http://127.0.0.1:8080", "server base URL")
	flag.StringVar(&cfg.stages, "stages", "50", "comma-separated concurrent room counts")
	flag.IntVar(&cfg.usersMin, "users-min", 3, "minimum users per room")
	flag.IntVar(&cfg.usersMax, "users-max", 8, "maximum users per room")
	flag.IntVar(&cfg.roundsMin, "rounds-min", 3, "minimum rounds per room")
	flag.IntVar(&cfg.roundsMax, "rounds-max", 12, "maximum rounds per room")
	flag.DurationVar(&cfg.delayMin, "delay-min", 5*time.Millisecond, "minimum user-action delay")
	flag.DurationVar(&cfg.delayMax, "delay-max", 50*time.Millisecond, "maximum user-action delay")
	flag.DurationVar(&cfg.roomRamp, "room-ramp", 250*time.Millisecond, "time over which rooms start; zero is a spike")
	flag.BoolVar(&cfg.webSockets, "websockets", true, "hold a heartbeat-aware WebSocket for every user")
	flag.Uint64Var(&cfg.seed, "seed", 20260924, "deterministic workload seed")
	flag.DurationVar(&cfg.stageTimeout, "stage-timeout", 20*time.Minute, "timeout for each stage")
	flag.Float64Var(&cfg.maxErrorRate, "max-error-rate", 0, "maximum failed-request ratio")
	flag.DurationVar(&cfg.maxP95, "max-p95", 500*time.Millisecond, "maximum p95 request latency")
	flag.Parse()
	return cfg
}

func parseStages(value string) ([]int, error) {
	parts := strings.Split(value, ",")
	stages := make([]int, 0, len(parts))
	for _, part := range parts {
		rooms, err := strconv.Atoi(strings.TrimSpace(part))
		if err != nil || rooms < 1 {
			return nil, errors.New("stages must be comma-separated positive integers")
		}
		stages = append(stages, rooms)
	}
	if len(stages) == 0 {
		return nil, errors.New("at least one stage is required")
	}
	return stages, nil
}
