#!/bin/bash

# =============================================================================
# MicroOCPP Simulator - One-Command Starter
# =============================================================================
# Combines generation and startup in a single command
#
# Usage:
#   ./start-simulators.sh [OPTIONS]
#
# Options:
#   --config FILE    Use an alternate config file
#   --clean          Remove previous generated files first
#   --logs           Show logs after startup
#   --detach         Run in background mode (default)
#   --foreground     Run in foreground mode
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/simulator-config.yml"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
CLEAN_MODE=false
SHOW_LOGS=false
DETACH_MODE=true
CUSTOM_CONFIG=""

# =============================================================================
# Helpers
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CUSTOM_CONFIG="$2"
                shift 2
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --logs)
                SHOW_LOGS=true
                shift
                ;;
            --detach)
                DETACH_MODE=true
                shift
                ;;
            --foreground)
                DETACH_MODE=false
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

One-command starter for MicroOCPP multi-container simulators.

OPTIONS:
    --config FILE    Use an alternate config file
    --clean          Remove previous generated files before startup
    --logs           Show container logs after startup
    --detach         Start containers in background mode (default)
    --foreground     Start containers in foreground mode
    -h, --help       Show this help

EXAMPLES:
    $0                           # Standard startup
    $0 --clean --logs            # Clean, start, and show logs
    $0 --config my-config.yml    # Alternate config
    $0 --foreground              # Foreground mode for debugging

WORKFLOW:
    1. Read simulator-config.yml
    2. Run generate-simulators.sh
    3. Start docker-compose -f docker-compose.generated.yml
    4. Optionally show logs or status
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
    
    # Use a custom config file when provided.
    if [[ -n "$CUSTOM_CONFIG" ]]; then
        if [[ -f "$CUSTOM_CONFIG" ]]; then
            CONFIG_FILE="$CUSTOM_CONFIG"
        else
            log_error "Config file not found: $CUSTOM_CONFIG"
        fi
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check whether the config file exists.
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
    fi
    
    # Check whether the generator script exists.
    if [[ ! -f "${SCRIPT_DIR}/generate-simulators.sh" ]]; then
        log_error "Generator script not found: ${SCRIPT_DIR}/generate-simulators.sh"
    fi
    
    # Check whether Docker is available.
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not available"
    fi
    
    # Check Docker Compose.
    local compose_cmd=""
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    elif command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        log_error "Neither 'docker compose' nor 'docker-compose' is available"
    fi
    
    log_success "Prerequisites satisfied"
}

show_configuration_summary() {
    log_info "Configuration summary:"
    echo "   Config file: $CONFIG_FILE"
    
    # Read the config when yq is available.
    if command -v yq &> /dev/null; then
        local v16_count
        local v201_count
        local v16_base_port
        local v201_base_port

        v16_count=$(yq eval '.simulators.v16.count // 0' "$CONFIG_FILE" 2>/dev/null || echo "?")
        v201_count=$(yq eval '.simulators.v201.count // 0' "$CONFIG_FILE" 2>/dev/null || echo "?")
        v16_base_port=$(
            yq eval '.simulators.v16.base_port // "?"' "$CONFIG_FILE" 2>/dev/null || echo "?"
        )
        v201_base_port=$(
            yq eval '.simulators.v201.base_port // "?"' "$CONFIG_FILE" 2>/dev/null || echo "?"
        )
        
        echo "   OCPP 1.6: $v16_count simulators (starting at port $v16_base_port)"
        echo "   OCPP 2.0.1: $v201_count simulators (starting at port $v201_base_port)"
        echo "   Total: $((v16_count + v201_count)) simulators"
    else
        log_warning "yq not installed. Skipping the detailed config summary."
    fi
}

run_generator() {
    log_info "Running multi-container generation..."
    
    local generator_args=""
    if [[ "$CLEAN_MODE" == true ]]; then
        generator_args="--clean"
    fi
    
    if [[ -n "$CUSTOM_CONFIG" ]]; then
        generator_args="$generator_args --config $CUSTOM_CONFIG"
    fi
    
    # Run the generator.
    bash "${SCRIPT_DIR}/generate-simulators.sh" $generator_args
    
    if [[ $? -eq 0 ]]; then
        log_success "Multi-container generation finished"
    else
        log_error "Multi-container generation failed"
    fi
}

start_containers() {
    log_info "Starting multi-container simulators..."
    
    local compose_file="${SCRIPT_DIR}/docker-compose.generated.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Generated Docker Compose file not found: $compose_file"
    fi
    
    # Resolve the Docker Compose command.
    local compose_cmd="docker compose"
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        if command -v docker-compose &> /dev/null; then
            compose_cmd="docker-compose"
        else
            log_error "Docker Compose is not available"
        fi
    fi
    
    # Start containers.
    local start_args="-f $compose_file up"
    if [[ "$DETACH_MODE" == true ]]; then
        start_args="$start_args -d"
    fi
    
    log_info "Running: $compose_cmd $start_args"
    $compose_cmd $start_args
    
    if [[ $? -eq 0 ]]; then
        log_success "Containers started successfully"
    else
        log_error "Container startup failed"
    fi
    
    # Show container status.
    log_info "Container status:"
    $compose_cmd -f "$compose_file" ps
}

show_logs() {
    if [[ "$SHOW_LOGS" == true ]]; then
        local compose_file="${SCRIPT_DIR}/docker-compose.generated.yml"
        
        log_info "Showing container logs (Ctrl+C to stop)..."
        sleep 2
        
        # Resolve the Docker Compose command.
        local compose_cmd="docker compose"
        if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
            compose_cmd="docker-compose"
        fi
        
        $compose_cmd -f "$compose_file" logs -f
    fi
}

print_success_summary() {
    echo ""
    log_success "Multi-container simulators started successfully"
    echo ""
    echo "Next steps:"
    echo "   Open frontend URLs based on the configured ports"
    echo "   Check status: docker-compose -f docker-compose.generated.yml ps"
    echo "   Show logs: docker-compose -f docker-compose.generated.yml logs -f"
    echo "   Stop: docker-compose -f docker-compose.generated.yml down"
    echo "   Clean up: ./cleanup-simulators.sh"
    echo ""
    echo "Maintenance:"
    echo "   Edit config: nano $CONFIG_FILE"
    echo "   Regenerate: ./generate-simulators.sh --clean"
    echo "   Restart: $0 --clean"
    echo ""
}

# =============================================================================
# Main entry point
# =============================================================================

main() {
    echo "MicroOCPP One-Command Starter"
    echo "========================================"
    echo ""
    
    # Parse arguments.
    parse_arguments "$@"
    
    # Check prerequisites.
    check_prerequisites
    
    # Show the configuration summary.
    show_configuration_summary
    
    echo ""
    
    # Run multi-container generation.
    run_generator
    
    echo ""
    
    # Start containers.
    start_containers
    
    echo ""
    
    # Show logs when requested.
    show_logs
    
    # Print the success summary in detach mode only.
    if [[ "$DETACH_MODE" == true ]]; then
        print_success_summary
    fi
}

# Run the main program.
main "$@"
