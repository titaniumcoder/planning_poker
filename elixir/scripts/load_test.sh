#!/bin/bash

# Planning Poker Load Testing Scripts

set -e

LOAD_TESTER_APP="planning-poker-load-tester"
TARGET_URL="https://planning-poker-rico.fly.dev"

show_help() {
    echo "Planning Poker Load Testing Tool"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  local                 Run load test locally"
    echo "  remote URL            Run load test against remote URL"
    echo "  deploy                Deploy load tester to Fly.io"
    echo "  run-remote            Run load test on Fly.io against production"
    echo "  stress URL            Run stress test against URL"
    echo "  help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 local --sessions 10"
    echo "  $0 remote https://my-app.fly.dev --sessions 50"
    echo "  $0 deploy"
    echo "  $0 run-remote --sessions 100"
    echo "  $0 stress https://planning-poker-rico.fly.dev"
    echo ""
}

run_local() {
    echo "🔥 Running local load test..."
    mix load_test "$@"
}

run_remote() {
    local url="$1"
    shift
    echo "🌐 Running remote load test against: $url"
    mix load_test --remote "$url" "$@"
}

deploy_load_tester() {
    echo "🚀 Deploying load tester to Fly.io..."
    
    if ! command -v flyctl &> /dev/null; then
        echo "❌ flyctl not found. Please install: https://fly.io/docs/getting-started/installing-flyctl/"
        exit 1
    fi
    
    # Check if app exists
    if ! flyctl apps list | grep -q "$LOAD_TESTER_APP"; then
        echo "📦 Creating new Fly.io app: $LOAD_TESTER_APP"
        flyctl apps create "$LOAD_TESTER_APP" --org personal
    fi
    
    echo "🔨 Building and deploying..."
    flyctl deploy --config fly.loadtest.toml --app "$LOAD_TESTER_APP"
    
    echo "✅ Load tester deployed successfully!"
    echo "📋 You can now run: $0 run-remote"
}

run_on_fly() {
    echo "☁️  Running load test on Fly.io against $TARGET_URL..."
    
    if ! flyctl apps list | grep -q "$LOAD_TESTER_APP"; then
        echo "❌ Load tester app not deployed. Run: $0 deploy"
        exit 1
    fi
    
    # Scale up if needed
    flyctl scale count 1 --app "$LOAD_TESTER_APP"
    
    # Run the load test
    flyctl machine run \
        --app "$LOAD_TESTER_APP" \
        --region fra \
        --memory 1gb \
        "planning-poker-load-tester" \
        --remote "$TARGET_URL" "$@"
}

stress_test() {
    local url="$1"
    shift
    echo "💥 Running stress test against: $url"
    mix load_test --remote "$url" --stress "$@"
}

# Main script logic
case "${1:-help}" in
    "local")
        shift
        run_local "$@"
        ;;
    "remote")
        if [ -z "$2" ]; then
            echo "❌ URL required for remote testing"
            echo "Usage: $0 remote URL [options]"
            exit 1
        fi
        url="$2"
        shift 2
        run_remote "$url" "$@"
        ;;
    "deploy")
        deploy_load_tester
        ;;
    "run-remote")
        shift
        run_on_fly "$@"
        ;;
    "stress")
        if [ -z "$2" ]; then
            echo "❌ URL required for stress testing"
            echo "Usage: $0 stress URL [options]"
            exit 1
        fi
        url="$2"
        shift 2
        stress_test "$url" "$@"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac