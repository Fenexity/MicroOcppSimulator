#!/bin/bash

# =============================================================================
# MicroOCPP Simulator - Multi-Container Cleanup
# =============================================================================
# Removes generated files and containers for the multi-container setup
#
# Usage:
#   ./cleanup-simulators.sh [--force] [--containers-only] [--files-only]
#
# Options:
#   --force           Skip confirmation
#   --containers-only Stop and remove containers only
#   --files-only      Remove files only
#
# WARNING: This script removes generated simulator artifacts permanently.
# =============================================================================

set -e

# =============================================================================
# Configuration and variables
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_COMPOSE="${SCRIPT_DIR}/docker-compose.generated.yml"
GENERATED_DIR="${SCRIPT_DIR}/mo_store_generated"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FORCE_MODE=false
CONTAINERS_ONLY=false
FILES_ONLY=false

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
            --force)
                FORCE_MODE=true
                shift
                ;;
            --containers-only)
                CONTAINERS_ONLY=true
                shift
                ;;
            --files-only)
                FILES_ONLY=true
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Remove generated multi-container simulator artifacts.

OPTIONS:
    --force           Skip confirmation
    --containers-only Stop and remove containers only
    --files-only      Remove generated files only
    -h, --help        Show this help

EXAMPLES:
    $0                      # Interactive cleanup
    $0 --force              # Full cleanup without confirmation
    $0 --containers-only    # Stop containers only
    $0 --files-only         # Remove generated files only

WARNING: This operation cannot be undone.
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
    
    # Validation: these flags are mutually exclusive.
    if [[ "$CONTAINERS_ONLY" == true && "$FILES_ONLY" == true ]]; then
        log_error "--containers-only and --files-only cannot be used together"
    fi
}

confirm_cleanup() {
    if [[ "$FORCE_MODE" == true ]]; then
        return 0
    fi
    
    echo ""
    echo "WARNING: Multi-container cleanup"
    echo "======================================="
    echo ""
    
    if [[ "$CONTAINERS_ONLY" == false ]]; then
        echo "Files and directories to remove:"
        [[ -f "$OUTPUT_COMPOSE" ]] && echo "   • docker-compose.generated.yml"
        [[ -d "$GENERATED_DIR" ]] && echo "   • mo_store_generated/ (all simulator configs)"
        echo ""
    fi
    
    if [[ "$FILES_ONLY" == false ]]; then
        echo "Container actions:"
        if [[ -f "$OUTPUT_COMPOSE" ]]; then
            echo "   • Stop all multi-container simulators"
            echo "   • Remove containers"
            echo "   • Keep images unless you remove them manually"
        else
            echo "   • No docker-compose.generated.yml found"
        fi
        echo ""
    fi
    
    echo "Continue? (y/N)"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Cleanup canceled"
        exit 0
    fi
}

stop_containers() {
    if [[ "$FILES_ONLY" == true ]]; then
        log_info "Skipping container cleanup (--files-only)"
        return 0
    fi
    
    log_info "Stopping and removing multi-container simulators..."
    
    if [[ ! -f "$OUTPUT_COMPOSE" ]]; then
        log_warning "docker-compose.generated.yml not found. No containers to stop."
        return 0
    fi
    
    # Check whether Docker is available.
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        log_error "Docker or Docker Compose is not available"
    fi
    
    # Use docker compose when available, otherwise docker-compose.
    local compose_cmd="docker compose"
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        if command -v docker-compose &> /dev/null; then
            compose_cmd="docker-compose"
        else
            log_error "Neither 'docker compose' nor 'docker-compose' is available"
        fi
    fi
    
    # Stop containers.
    log_info "Stopping containers..."
    if $compose_cmd -f "$OUTPUT_COMPOSE" ps -q | grep -q .; then
        $compose_cmd -f "$OUTPUT_COMPOSE" down --remove-orphans
        log_success "Containers stopped and removed"
    else
        log_info "No running containers found"
    fi
    
    # Remove potential orphaned containers.
    log_info "Searching for orphaned multi-container simulator containers..."
    local orphaned_containers
    orphaned_containers=$(
        docker ps -a --filter "name=microocpp-sim-v" --format "{{.Names}}" 2>/dev/null || true
    )
    
    if [[ -n "$orphaned_containers" ]]; then
        log_warning "Found orphaned containers:"
        echo "$orphaned_containers" | while read -r container; do
            echo "   • $container"
        done
        
        if [[ "$FORCE_MODE" == true ]]; then
            echo "$orphaned_containers" | xargs -r docker rm -f
            log_success "Orphaned containers removed"
        else
            echo ""
            echo "Remove orphaned containers? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "$orphaned_containers" | xargs -r docker rm -f
                log_success "Orphaned containers removed"
            fi
        fi
    else
        log_info "No orphaned containers found"
    fi
}

cleanup_files() {
    if [[ "$CONTAINERS_ONLY" == true ]]; then
        log_info "Skipping file cleanup (--containers-only)"
        return 0
    fi
    
    log_info "Removing generated files..."
    
    local cleaned_files=0
    
    # Remove the generated Docker Compose file.
    if [[ -f "$OUTPUT_COMPOSE" ]]; then
        rm "$OUTPUT_COMPOSE"
        log_info "Removed: docker-compose.generated.yml"
        cleaned_files=$((cleaned_files + 1))
    fi
    
    # Remove generated mo_store directories.
    if [[ -d "$GENERATED_DIR" ]]; then
        local store_count
        store_count=$(find "$GENERATED_DIR" -maxdepth 1 -type d -name "sim_*" | wc -l)
        rm -rf "$GENERATED_DIR"
        log_info "Removed: mo_store_generated/ ($store_count simulator configs)"
        cleaned_files=$((cleaned_files + 1))
    fi
    
    # Optionally remove template cache in force mode.
    if [[ "$FORCE_MODE" == true && -d "$TEMPLATES_DIR" ]]; then
        if [[ -d "${TEMPLATES_DIR}/mo_store_v16_template" \
            || -d "${TEMPLATES_DIR}/mo_store_v201_template" ]]; then
            log_info "Removing template cache..."
            rm -rf \
                "${TEMPLATES_DIR}/mo_store_v16_template" \
                "${TEMPLATES_DIR}/mo_store_v201_template" \
                2>/dev/null || true
            log_info "Template cache removed"
            cleaned_files=$((cleaned_files + 1))
        fi
    fi
    
    if [[ $cleaned_files -eq 0 ]]; then
        log_info "No generated files found"
    else
        log_success "Removed $cleaned_files generated file groups"
    fi
}

cleanup_docker_resources() {
    if [[ "$FILES_ONLY" == true || "$FORCE_MODE" == false ]]; then
        return 0
    fi
    
    log_info "Cleaning Docker resources..."
    
    # Remove dangling images in force mode.
    local unused_images=$(docker images --filter "dangling=true" -q 2>/dev/null || true)
    if [[ -n "$unused_images" ]]; then
        docker rmi $unused_images 2>/dev/null || true
        log_info "Removed dangling Docker images"
    fi
    
    # Prune Docker volumes.
    docker volume prune -f &>/dev/null || true
    log_info "Pruned Docker volumes"
}

print_summary() {
    echo ""
    log_success "Multi-container cleanup finished"
    echo ""
    echo "Actions performed:"
    
    if [[ "$FILES_ONLY" == false ]]; then
        echo "   Containers stopped and removed"
    fi
    
    if [[ "$CONTAINERS_ONLY" == false ]]; then
        echo "   Generated files removed"
        echo "   mo_store directories cleaned"
    fi
    
    if [[ "$FORCE_MODE" == true && "$FILES_ONLY" == false ]]; then
        echo "   Docker resources cleaned"
    fi
    
    echo ""
    echo "Next steps:"
    echo "   1. Edit simulator-config.yml as needed"
    echo "   2. Run ./generate-simulators.sh"
    echo "   3. Start with: docker-compose -f docker-compose.generated.yml up -d"
    echo ""
    echo "Tip: use --containers-only to stop containers without deleting configs."
}

check_running_containers() {
    if [[ ! -f "$OUTPUT_COMPOSE" ]]; then
        return 0
    fi
    
    # Check whether containers from the generated compose file are running.
    local running_containers
    running_containers=$(docker-compose -f "$OUTPUT_COMPOSE" ps -q 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_containers" -gt 0 ]]; then
        log_warning \
            "$running_containers containers from docker-compose.generated.yml are still running"
        echo "   Use './cleanup-simulators.sh --containers-only' to stop them"
    fi
}

# =============================================================================
# Main entry point
# =============================================================================

main() {
    echo "MicroOCPP Multi-Container Cleanup"
    echo "============================================="
    echo ""
    
    # Parse arguments.
    parse_arguments "$@"
    
    # Check the current state.
    check_running_containers
    
    # Ask for confirmation.
    confirm_cleanup
    
    echo ""
    log_info "Starting multi-container cleanup..."
    
    # Stop and remove containers.
    stop_containers
    
    # Clean files.
    cleanup_files
    
    # Clean Docker resources in force mode.
    cleanup_docker_resources
    
    # Print summary.
    print_summary
}

# Run the main program.
main "$@"
