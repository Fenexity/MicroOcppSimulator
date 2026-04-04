#!/bin/bash

# =============================================================================
# MicroOCPP Simulator - Multi-Container Generator
# =============================================================================
# Generate Docker Compose config and mo_store directories from
# simulator-config.yml
#
# Usage:
#   ./generate-simulators.sh [--clean] [--config CONFIG_FILE]
#
# Options:
#   --clean       Remove previously generated files first
#   --config      Use an alternate config file
#
# Output:
#   - docker-compose.generated.yml
#   - mo_store_generated/sim_*/ directories
#   - updated templates
# =============================================================================

set -e  # Exit on failure

# =============================================================================
# Configuration and variables
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/simulator-config.yml"
OUTPUT_COMPOSE="${SCRIPT_DIR}/docker-compose.generated.yml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
GENERATED_DIR="${SCRIPT_DIR}/mo_store_generated"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
CLEAN_MODE=false
VERBOSE=false

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

check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check whether yq is installed for YAML parsing.
    if ! command -v yq &> /dev/null; then
        log_error "yq is not installed. Install it with brew install yq or apt-get install yq."
    fi
    
    # Check whether Docker is available.
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not available"
    fi
    
    log_success "Dependencies available"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Generate Docker Compose config for multiple OCPP simulators.

OPTIONS:
    --clean         Remove previous generated files
    --config FILE   Use an alternate config file
    --verbose       Detailed output
    -h, --help      Show this help

EXAMPLES:
    $0                              # Use the default config
    $0 --clean                      # Clean and regenerate
    $0 --config custom-config.yml   # Alternate config
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
}

validate_config() {
    log_info "Validating config file: $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
    fi
    
    # Check the basic YAML structure.
    if ! yq eval '.simulators' "$CONFIG_FILE" > /dev/null 2>&1; then
        log_error "Invalid YAML structure in config file"
    fi
    
    # Check whether at least one simulator config exists.
    local simulator_count=$(yq eval '.simulators | keys | length' "$CONFIG_FILE")
    if [[ "$simulator_count" -eq 0 ]]; then
        log_error "No simulator configurations found in $CONFIG_FILE"
    fi
    
    log_success "Config file is valid"
}

cleanup_previous() {
    if [[ "$CLEAN_MODE" == true ]]; then
        log_info "Cleaning previous generated files..."
        
        # Remove the generated Docker Compose file.
        if [[ -f "$OUTPUT_COMPOSE" ]]; then
            rm "$OUTPUT_COMPOSE"
            log_info "Removed: docker-compose.generated.yml"
        fi
        
        # Remove generated mo_store directories.
        if [[ -d "$GENERATED_DIR" ]]; then
            rm -rf "$GENERATED_DIR"
            log_info "Removed: mo_store_generated/"
        fi
        
        log_success "Cleanup finished"
    fi
}

create_templates() {
    log_info "Creating or refreshing templates..."
    
    mkdir -p "$TEMPLATES_DIR"
    
    # Create the OCPP 1.6 template.
    if [[ -d "${SCRIPT_DIR}/mo_store_v16" ]]; then
        log_info "Creating OCPP 1.6 template from mo_store_v16/"
        cp -r "${SCRIPT_DIR}/mo_store_v16" "${TEMPLATES_DIR}/mo_store_v16_template"
        
        # Replace specific values with placeholders in ws-conn.jsn.
        if [[ -f "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn" ]]; then
            sed -i.bak 's/"charger-1\.6"/"{{CHARGER_ID}}"/g' \
                "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn"
            sed -i.bak 's|ws://[^/]*/charger-1\.6|ws://{{CITRINEOS_IP}}:8092/{{CHARGER_ID}}|g' \
                "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn"
            rm "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn.bak"
        fi
    else
        log_warning "mo_store_v16/ not found. Skipping the OCPP 1.6 template."
    fi
    
    # Create the OCPP 2.0.1 template.
    if [[ -d "${SCRIPT_DIR}/mo_store_v201" ]]; then
        log_info "Creating OCPP 2.0.1 template from mo_store_v201/"
        cp -r "${SCRIPT_DIR}/mo_store_v201" "${TEMPLATES_DIR}/mo_store_v201_template"
        
        # Replace specific values with placeholders in ws-conn-v201.jsn.
        if [[ -f "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn" ]]; then
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' \
                "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn"
            sed -i.bak 's|ws://[^/]*/charger-201|ws://{{CITRINEOS_IP}}:8082/{{CHARGER_ID}}|g' \
                "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn"
            sed -i.bak 's/"fenexity_test_2025"/"{{AUTH_PASSWORD}}"/g' \
                "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn"
            rm "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn.bak"
        fi
        
        # Replace values in the legacy ws-conn.jsn format.
        if [[ -f "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn" ]]; then
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' \
                "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn"
            sed -i.bak 's|ws://[^/]*/charger-201|ws://{{CITRINEOS_IP}}:8082/{{CHARGER_ID}}|g' \
                "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn"
            sed -i.bak 's/"fenexity_test_2025"/"{{AUTH_PASSWORD}}"/g' \
                "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn"
            rm "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn.bak"
        fi
    else
        log_warning "mo_store_v201/ not found. Skipping the OCPP 2.0.1 template."
    fi
    
    log_success "Templates created or updated"
}

generate_mo_store() {
    local version="$1"
    local charger_id="$2"
    local csms_url="$3"
    local auth_password="$4"
    local output_dir="$5"
    
    log_info "Generating mo_store for $charger_id..."
    
    # Resolve the template directory.
    local template_dir
    if [[ "$version" == "1.6" ]]; then
        template_dir="${TEMPLATES_DIR}/mo_store_v16_template"
    elif [[ "$version" == "2.0.1" ]]; then
        template_dir="${TEMPLATES_DIR}/mo_store_v201_template"
    else
        log_error "Unknown OCPP version: $version"
    fi
    
    if [[ ! -d "$template_dir" ]]; then
        log_error "Template directory not found: $template_dir"
    fi
    
    # Copy the template files.
    mkdir -p "$output_dir"
    cp -r "${template_dir}"/* "$output_dir/"
    
    # Detect the CitrineOS IP as in the original configure-citrineos.sh.
    local citrineos_service
    citrineos_service=$(
        yq eval '.global.citrineos_service // "fenexity-citrineos"' "$CONFIG_FILE"
    )
    local citrineos_ip
    citrineos_ip=$(
        docker inspect "$citrineos_service" \
            --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
            2>/dev/null || echo ""
    )
    
    if [[ -z "$citrineos_ip" || "$citrineos_ip" == "null" ]]; then
        log_warning "Could not detect a CitrineOS IP. Keeping the placeholder."
        citrineos_ip="{{CITRINEOS_IP}}"
    fi
    
    # Replace the service name with the detected IP in the CSMS URL.
    local csms_url_with_ip
    csms_url_with_ip=$(echo "$csms_url" | sed "s/citrineos/$citrineos_ip/g")
    
    # Replace placeholders in all JSON files.
    find "$output_dir" -name "*.jsn" -o -name "*.json" | while read -r file; do
        sed -i.bak "s/{{CHARGER_ID}}/$charger_id/g" "$file"
        sed -i.bak "s|{{CSMS_URL}}|$csms_url_with_ip|g" "$file"
        sed -i.bak "s/{{AUTH_PASSWORD}}/$auth_password/g" "$file"
        sed -i.bak "s/{{CITRINEOS_IP}}/$citrineos_ip/g" "$file"
        rm "$file.bak"
    done
    
    log_success "Created mo_store for $charger_id: $output_dir"
}

generate_docker_compose() {
    log_info "Generating Docker Compose configuration..."
    
    # Write the Docker Compose header.
    cat > "$OUTPUT_COMPOSE" << 'EOF'
# =============================================================================
# MicroOCPP Simulator - Generated Multi-Container Configuration
# =============================================================================
# WARNING: This file is generated automatically.
# Changes here will be overwritten by the next generate-simulators.sh run.
#
# Edit simulator-config.yml for configuration changes, then run:
# ./generate-simulators.sh
# =============================================================================

EOF

    # Write network configuration.
    local network_name=$(yq eval '.global.network_name // "fnx-platform-net"' "$CONFIG_FILE")
    cat >> "$OUTPUT_COMPOSE" << EOF
networks:
  default:
    driver: bridge
    name: $network_name
    external: true

services:
EOF

    # Configuration service used for CitrineOS IP detection.
    cat >> "$OUTPUT_COMPOSE" << 'EOF'
  # =============================================================================
  # Configuration service runs before the simulators start.
  # =============================================================================
  microocpp-multi-config:
    image: alpine:latest
    container_name: microocpp-multi-config
    platform: linux/arm64
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./configure-citrineos.sh:/configure-citrineos.sh:ro
EOF

    # Add mo_store volume mounts for the configuration service.
    local simulator_versions=$(yq eval '.simulators | keys | .[]' "$CONFIG_FILE")
    while IFS= read -r version; do
        local count=$(yq eval ".simulators.${version}.count" "$CONFIG_FILE")
        local container_prefix=$(yq eval ".simulators.${version}.container_prefix" "$CONFIG_FILE")
        
        for ((i=1; i<=count; i++)); do
            local sim_id=$(printf "%03d" $i)
            local mo_store_path="./mo_store_generated/sim_${version}_${sim_id}"
            echo "      - ${mo_store_path}:/output/sim_${version}_${sim_id}" >> "$OUTPUT_COMPOSE"
        done
    done <<< "$simulator_versions"

    # Configuration service command.
    cat >> "$OUTPUT_COMPOSE" << 'EOF'
    command: >
      sh -c "
      echo 'Starting multi-simulator configuration...';
      apk add --no-cache bash grep curl docker-cli;
      echo 'Multi-simulator configuration finished.';
      "
    restart: "no"

EOF

    # Generate services for all simulator versions.
    while IFS= read -r version; do
        generate_simulator_services "$version"
    done <<< "$simulator_versions"

    log_success "Created Docker Compose configuration: $OUTPUT_COMPOSE"
}

generate_simulator_services() {
    local version="$1"
    local count=$(yq eval ".simulators.${version}.count" "$CONFIG_FILE")
    local base_port=$(yq eval ".simulators.${version}.base_port" "$CONFIG_FILE")
    local ocpp_version=$(yq eval ".simulators.${version}.ocpp_version" "$CONFIG_FILE")
    local csms_url_template=$(yq eval ".simulators.${version}.csms_url_template" "$CONFIG_FILE")
    local base_charger_id=$(yq eval ".simulators.${version}.base_charger_id" "$CONFIG_FILE")
    local container_prefix=$(yq eval ".simulators.${version}.container_prefix" "$CONFIG_FILE")
    local auth_password=$(yq eval ".simulators.${version}.auth_password // \"\"" "$CONFIG_FILE")
    
    log_info "Generating $count simulators for OCPP $ocpp_version..."
    
    # Header for this version section.
    cat >> "$OUTPUT_COMPOSE" << EOF
  # =============================================================================
  # OCPP $ocpp_version simulators ($count containers)
  # =============================================================================
EOF

    # Generate each simulator.
    for ((i=1; i<=count; i++)); do
        local sim_id=$(printf "%03d" $i)
        local charger_id="${base_charger_id}-${sim_id}"
        local port=$((base_port + i - 1))
        local container_name="${container_prefix}-${sim_id}"
        local csms_url="${csms_url_template/\{charger_id\}/$charger_id}"
        local mo_store_path="./mo_store_generated/sim_${version}_${sim_id}"
        
        # Create mo_store for this simulator.
        mkdir -p "$GENERATED_DIR"
        generate_mo_store \
            "$ocpp_version" \
            "$charger_id" \
            "$csms_url" \
            "$auth_password" \
            "${GENERATED_DIR}/sim_${version}_${sim_id}"
        
        # Docker service definition.
        cat >> "$OUTPUT_COMPOSE" << EOF
  $container_name:
    build:
      context: .
      dockerfile: Dockerfile.arm64
      args:
        OCPP_VERSION: "$ocpp_version"
        SIMULATOR_PORT: "8000"
        CHARGER_ID: "$charger_id"
        API_PORT: "$port"
    container_name: $container_name
    platform: linux/arm64
    ports:
      - "$port:8000"
    volumes:
      - $mo_store_path:/MicroOcppSimulator/mo_store:rw
      - ./config:/MicroOcppSimulator/config:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - OCPP_VERSION=$ocpp_version
      - CHARGER_ID=$charger_id
      - SIMULATOR_PORT=8000
      - API_PORT=$port
      - CENTRAL_SYSTEM_URL=$csms_url
EOF

        # Append additional environment variables.
        local env_vars=$(yq eval ".simulators.${version}.environment // {}" "$CONFIG_FILE")
        if [[ "$env_vars" != "null" && "$env_vars" != "{}" ]]; then
            yq eval \
                ".simulators.${version}.environment | to_entries | .[]" \
                "$CONFIG_FILE" \
                | yq eval '"      - " + .key + "=" + .value' - \
                >> "$OUTPUT_COMPOSE"
        fi

        # Finish the service definition.
        cat >> "$OUTPUT_COMPOSE" << EOF
    networks:
      - default
    restart: unless-stopped
    depends_on:
      - microocpp-multi-config
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

EOF
    done
}

print_summary() {
    log_success "Multi-container generation finished"
    echo ""
    echo "Generated files:"
    echo "   Docker Compose: $OUTPUT_COMPOSE"
    echo "   mo_store directories: $GENERATED_DIR/"
    echo ""
    echo "Simulator summary:"
    
    local simulator_versions=$(yq eval '.simulators | keys | .[]' "$CONFIG_FILE")
    local total_simulators=0
    
    while IFS= read -r version; do
        local count=$(yq eval ".simulators.${version}.count" "$CONFIG_FILE")
        local base_port=$(yq eval ".simulators.${version}.base_port" "$CONFIG_FILE")
        local ocpp_version=$(yq eval ".simulators.${version}.ocpp_version" "$CONFIG_FILE")
        
        echo "   OCPP $ocpp_version: $count simulators "
        echo "   (ports $base_port-$((base_port + count - 1)))"
        total_simulators=$((total_simulators + count))
    done <<< "$simulator_versions"
    
    echo "   Total: $total_simulators simulators"
    echo ""
    echo "Next steps:"
    echo "   1. docker-compose -f docker-compose.generated.yml up -d"
    echo "   2. Wait for the containers to pass their health checks"
    echo "   3. Open http://localhost:[PORT] for each simulator"
    echo ""
    echo "Management:"
    echo "   • Stop: docker-compose -f docker-compose.generated.yml down"
    echo "   • Logs: docker-compose -f docker-compose.generated.yml logs -f [service]"
    echo "   • Clean up: ./cleanup-simulators.sh"
}

# =============================================================================
# Main entry point
# =============================================================================

main() {
    echo "MicroOCPP Multi-Container Generator"
    echo "============================================="
    echo ""
    
    # Parse arguments.
    parse_arguments "$@"
    
    # Check dependencies.
    check_dependencies
    
    # Validate config.
    validate_config
    
    # Clean previous generated files.
    cleanup_previous
    
    # Create or refresh templates.
    create_templates
    
    # Generate Docker Compose config.
    generate_docker_compose
    
    # Print the summary.
    print_summary
}

# Run the main program.
main "$@"
