#!/bin/bash

# =============================================================================
# MicroOCPP Simulator - Depot Generator
# =============================================================================
# Generate OCPP simulators from charger CSV files
#
# Usage:
#   ./generate-depot.sh <CSV_FILE> [OCPP_VERSION]
#   ./generate-depot.sh depot-data/chargers-darmstadt.csv 1.6
#   ./generate-depot.sh depot-data/chargers-hamburg.csv 2.0.1
#
# Parameters:
#   CSV_FILE      - path to the charger CSV file
#   OCPP_VERSION  - OCPP version (1.6 or 2.0.1, default: 1.6)
#
# CSV format (charger file):
#   - must contain a "charger_id" column
#   - must contain a "max_power_kw" column (power in kW)
#   - multiple rows per charger allowed (one per connector)
#   - unique charger_id values are detected automatically
#
# Output:
#   - simulator-config-depot.yml (generated configuration)
#   - docker-compose-depot.yml (Docker Compose for the depot setup)
#   - mo_store_depot/ (generated mo_store directories)
# =============================================================================

set -e  # Exit on failure

# =============================================================================
# Configuration and variables
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE=""
OCPP_VERSION="1.6"  # Default
NO_START=false      # Default: start containers automatically
OUTPUT_CONFIG="${SCRIPT_DIR}/simulator-config-depot.yml"
OUTPUT_COMPOSE="${SCRIPT_DIR}/docker-compose-depot.yml"
GENERATED_DIR="${SCRIPT_DIR}/mo_store_depot"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    echo "MicroOCPP Depot Generator"
    echo "====================================="
    echo ""
    echo "Usage:"
    echo "  $0 <CSV_FILE> [OCPP_VERSION] [--no-start]"
    echo "  $0 --update-url"
    echo ""
    echo "Parameters:"
    echo "  CSV_FILE      Path to the charger CSV file (required)"
    echo "  OCPP_VERSION  OCPP version: 1.6 or 2.0.1 (default: 1.6)"
    echo "  --no-start    Generate files only, do not start containers"
    echo "  --update-url  Refresh the CitrineOS IP and restart containers"
    echo ""
    echo "Examples:"
    echo "  $0 depot-data/chargers-darmstadt.csv"
    echo "  $0 depot-data/chargers-darmstadt.csv 1.6"
    echo "  $0 depot-data/chargers-hamburg.csv 2.0.1 --no-start"
    echo "  $0 --update-url                    # refresh IP + restart containers"
    echo ""
    echo "CSV requirements (charger file):"
    echo "  - Must contain a header row with a 'charger_id' column"
    echo "  - Must contain a 'max_power_kw' column (power in kW)"
    echo "  - Multiple rows per charger allowed (one per connector)"
    echo "  - Unique charger_id values are detected automatically"
    echo ""
    echo "Output:"
    echo "  simulator-config-depot.yml"
    echo "  docker-compose-depot.yml"
    echo "  mo_store_depot/"
}

# =============================================================================
# Validation helpers
# =============================================================================

validate_csv_file() {
    local csv_file="$1"
    
    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV file not found: $csv_file"
        return 1
    fi
    
    local header
    header=$(head -1 "$csv_file")
    
    if ! echo "$header" | grep -q "charger_id"; then
        log_error "CSV file must contain a 'charger_id' column"
        log_error "Detected headers: $header"
        return 1
    fi
    
    if ! echo "$header" | grep -q "max_power_kw"; then
        log_error "CSV file must contain a 'max_power_kw' column"
        log_error "Detected headers: $header"
        return 1
    fi
    
    log_success "Validated CSV file: $csv_file"
    return 0
}

validate_ocpp_version() {
    local version="$1"
    
    if [[ "$version" != "1.6" && "$version" != "2.0.1" ]]; then
        log_error "Invalid OCPP version: $version"
        log_error "Allowed versions: 1.6, 2.0.1"
        return 1
    fi
    
    log_success "Validated OCPP version: $version"
    return 0
}

# =============================================================================
# CSV parsing helpers
# =============================================================================

extract_charging_stations() {
    local csv_file="$1"
    local temp_file=$(mktemp)
    
    log_info "Extracting charger IDs from the CSV..." >&2
    
    local header=$(head -1 "$csv_file")
    local column_index
    column_index=$(
        echo "$header" \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
            | grep -n "^charger_id$" \
            | cut -d: -f1
    )
    
    if [[ -z "$column_index" ]]; then
        log_error "charger_id column not found"
        log_error "Header row: $header"
        log_error "Normalized columns:"
        echo "$header" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | nl >&2
        rm -f "$temp_file"
        return 1
    fi
    
    log_info "Found charger_id in column $column_index" >&2
    
    tail -n +2 "$csv_file" | \
        cut -d',' -f"$column_index" | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -v '^$' | \
        sort -u > "$temp_file"
    
    local count=$(wc -l < "$temp_file")
    log_success "Found $count unique chargers" >&2
    
    if [[ $count -gt 0 ]]; then
        log_info "Example IDs:" >&2
        head -5 "$temp_file" | sed 's/^/  - /' >&2
        if [[ $count -gt 5 ]]; then
            echo "  ... and $(($count - 5)) more" >&2
        fi
    fi
    
    echo "$temp_file"
}

# =============================================================================
# CitrineOS IP detection
# =============================================================================

is_valid_ipv4() {
    echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

detect_citrineos_ip() {
    local citrineos_service="fenexity-citrineos"
    local raw_ip
    
    log_info "Detecting the CitrineOS IP address..." >&2
    
    raw_ip=$(
        docker inspect "$citrineos_service" \
            --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
            2>/dev/null || echo ""
    )
    
    if is_valid_ipv4 "$raw_ip"; then
        log_success "Detected CitrineOS IP: $raw_ip" >&2
        echo "$raw_ip"
        return 0
    fi
    
    log_warning "CitrineOS container '$citrineos_service' has no valid IP "
    log_warning "(response: '$raw_ip')" >&2
    log_info "Available containers:" >&2
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(citrineos|CitrineOS)" >&2 \
        || log_warning "No CitrineOS containers found" >&2
    
    echo ""
    return 1
}

update_citrineos_ip_in_containers() {
    local new_ip="$1"
    
    if [[ -z "$new_ip" ]]; then
        log_error "No IP address provided"
        return 1
    fi
    
    if ! is_valid_ipv4 "$new_ip"; then
        log_error "Invalid IP address: '$new_ip'"
        return 1
    fi
    
    log_info "Updating the CitrineOS IP ($new_ip) in all depot containers..."
    
    local containers
    containers=$(docker ps --format "{{.Names}}" | grep "^sim-CS-" || echo "")
    
    if [[ -z "$containers" ]]; then
        log_warning "No running depot containers found"
        return 0
    fi
    
    local updated_count=0
    local total_count=0
    
    while IFS= read -r container_name; do
        [[ -z "$container_name" ]] && continue
        ((total_count++))
        
        log_info "Updating $container_name..."
        
        if docker exec "$container_name" sh -c "
            CONFIG_FILE=/MicroOcppSimulator/mo_store/ws-conn.jsn
            if [ -f \"\$CONFIG_FILE\" ]; then
                sed -i 's|ws://[^:]*:|ws://$new_ip:|g' \"\$CONFIG_FILE\"
                echo 'ws-conn.jsn updated'
            else
                echo 'ws-conn.jsn not found'
                exit 1
            fi
        " 2>/dev/null; then
            ((updated_count++))
            log_success "Updated $container_name"
        else
            log_error "Failed to update $container_name"
        fi
    done <<< "$containers"
    
    log_success "IP update finished: $updated_count/$total_count containers updated"
    
    return 0
}

restart_depot_containers() {
    local restart_mode="$1"  # "all" or "updated"
    
    log_info "Restarting depot containers..."
    
    if [[ ! -f "docker-compose-depot.yml" ]]; then
        log_error "docker-compose-depot.yml not found"
        log_info "Run './generate-depot.sh <csv-file> <ocpp-version>' first"
        return 1
    fi
    
    # Check whether containers are already running.
    local running_containers
    running_containers=$(
        docker-compose -f docker-compose-depot.yml ps -q 2>/dev/null | wc -l | tr -d ' '
    )
    
    if [[ "$running_containers" -eq 0 ]]; then
        log_warning "No running depot containers found"
        log_info "Starting containers..."
        if docker-compose -f docker-compose-depot.yml up -d; then
            log_success "Started containers successfully"
        else
            log_error "Failed to start containers"
            return 1
        fi
    else
        log_info "Restarting $running_containers containers..."
        if docker-compose -f docker-compose-depot.yml restart; then
            log_success "Restarted containers successfully"
        else
            log_error "Failed to restart containers"
            return 1
        fi
    fi
    
    # Wait briefly and then check status.
    sleep 5
    local healthy_containers
    healthy_containers=$(
        docker-compose -f docker-compose-depot.yml ps --filter "status=running" -q \
            2>/dev/null | wc -l | tr -d ' '
    )
    
    log_info "Status: $healthy_containers/$running_containers containers running"
    
    return 0
}

# =============================================================================
# Charger power extraction
# =============================================================================

extract_max_power_from_csv() {
    local csv_file="$1"
    local charger_id="$2"
    
    log_info "Extracting max_power for $charger_id from the CSV..." >&2
    
    local max_power_kw=$(awk -F',' -v cid="$charger_id" '
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                col = $i;
                gsub(/^[ \t]+|[ \t]+$/, "", col);
                if (col == "charger_id") id_col = i;
                if (col == "max_power_kw") power_col = i;
            }
            next;
        }
        id_col && power_col {
            id = $id_col;
            gsub(/^[ \t]+|[ \t]+$/, "", id);
            if (id == cid) {
                val = $power_col;
                gsub(/^[ \t]+|[ \t]+$/, "", val);
                if (val != "" && val+0 > 0) {
                    print val;
                    exit;
                }
            }
        }
    ' "$csv_file")
    
    if [[ -n "$max_power_kw" && "$max_power_kw" != "0" ]]; then
        local power_w=$((max_power_kw * 1000))
        log_info "Found ${max_power_kw}kW = ${power_w}W for $charger_id" >&2
        echo "$power_w"
    else
        log_warning "No max_power_kw found for $charger_id. Using default 11kW." >&2
        echo "11000"
    fi
}

# =============================================================================
# Configuration generation
# =============================================================================

generate_simulator_config() {
    local charging_stations_file="$1"
    local ocpp_version="$2"
    local csv_filename="$3"
    
    log_info "Generating simulator configuration..."
    
    local count=$(wc -l < "$charging_stations_file")
    local version_key
    local base_port
    local csms_url_template
    local env_vars
    
    if [[ "$ocpp_version" == "1.6" ]]; then
        version_key="v16"
        base_port=7101
        csms_url_template="ws://citrineos:8081/{charger_id}"
        env_vars="MO_ENABLE_V201: \"0\""
    else
        version_key="v201"
        base_port=7201
        csms_url_template="ws://citrineos:8081/{charger_id}"
        env_vars="MO_ENABLE_V201: \"1\""
    fi
    
    cat > "$OUTPUT_CONFIG" << EOF
# =============================================================================
# MicroOCPP Simulator - Depot Configuration
# =============================================================================
# Generated automatically from: $csv_filename
# OCPP Version: $ocpp_version
# Charging stations: $count
# Generated at: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

global:
  network_name: "fnx-platform-net"
  citrineos_service: "fenexity-citrineos"
  mo_store_base_path: "./mo_store_depot"

simulators:
  $version_key:
    count: $count
    base_port: $base_port
    ocpp_version: "$ocpp_version"
    csms_url_template: "$csms_url_template"
    base_charger_id: "depot-charger"
    container_prefix: "depot-sim-$version_key"
EOF

    if [[ "$ocpp_version" == "2.0.1" ]]; then
        cat >> "$OUTPUT_CONFIG" << EOF
    auth_password: ""
EOF
    fi

    cat >> "$OUTPUT_CONFIG" << EOF
    environment:
      $env_vars
    # Depot-specific IDs assigned by the generator.
    depot_ids:
EOF

    # Add all charging station IDs.
    local index=1
    while IFS= read -r station_id; do
        echo "      - id: \"$station_id\"" >> "$OUTPUT_CONFIG"
        echo "        index: $index" >> "$OUTPUT_CONFIG"
        ((index++))
    done < "$charging_stations_file"

    cat >> "$OUTPUT_CONFIG" << EOF

templates:
  v16_mo_store: "./mo_store_v16"
  v201_mo_store: "./mo_store_v201"

docker:
  dockerfile: "Dockerfile"
  context: "."
  restart_policy: "unless-stopped"
  healthcheck:
    test: '["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000"]'
    interval: "30s"
    timeout: "10s"
    retries: 3
    start_period: "30s"
EOF

    log_success "Created configuration: $OUTPUT_CONFIG"
}


# =============================================================================
# Docker Compose generation
# =============================================================================

generate_docker_compose() {
    local charging_stations_file="$1"
    local ocpp_version="$2"
    local csv_file="$3"
    
    log_info "Generating Docker Compose configuration..."
    
    local version_key
    
    if [[ "$ocpp_version" == "1.6" ]]; then
        version_key="v16"
    else
        version_key="v201"
    fi
    
    # Docker Compose header.
    cat > "$OUTPUT_COMPOSE" << EOF
# =============================================================================
# MicroOCPP Simulator - Depot Docker Compose
# =============================================================================
# Generated automatically from the depot CSV
# OCPP Version: $ocpp_version
# Generated at: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# Docker Compose version field omitted intentionally

networks:
  fnx-platform-net:
    external: true

services:
  depot-config:
    image: alpine:latest
    container_name: depot-multi-config
    command: >
      sh -c "
        echo 'Starting depot multi-container configuration...'
        echo 'OCPP version: $ocpp_version'
        echo 'Total simulators: $(wc -l < "$charging_stations_file")'
        echo 'Configuration completed.'
        sleep 5
      "
    networks:
      - fnx-platform-net

EOF

    # Generate services for each charging station.
    local index=1
    local base_port
    
    if [[ "$ocpp_version" == "1.6" ]]; then
        base_port=7101
    else
        base_port=7201
    fi
    
    while IFS= read -r station_id; do
        local port=$((base_port + index - 1))
        local container_name="sim-${station_id}"
        local service_name="sim-${station_id}"
        local mo_store_volume
        mo_store_volume="./mo_store_depot/depot_${version_key}_$(printf "%03d" $index)"
        
        # Resolve the image name from the OCPP version.
        local image_name
        if [[ "$ocpp_version" == "1.6" ]]; then
            image_name="microocpp-sim-v16:latest"
        else
            image_name="microocpp-sim-v201:latest"
        fi
        
        # Extract max power from the CSV.
        local max_power_w=$(extract_max_power_from_csv "$csv_file" "$station_id")

        cat >> "$OUTPUT_COMPOSE" << EOF
  $service_name:
    image: $image_name
    container_name: $container_name
    ports:
      - "$port:8000"
    volumes:
      - "$mo_store_volume:/MicroOcppSimulator/mo_store:rw"
      - "./config:/MicroOcppSimulator/config:ro"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks:
      - fnx-platform-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      - depot-config
    environment:
      - OCPP_VERSION=$ocpp_version
      - CHARGER_ID=$station_id
      - SIMULATOR_PORT=8000
      - API_PORT=$port
      - MAX_POWER_W=$max_power_w
EOF
        
        if [[ "$ocpp_version" == "1.6" ]]; then
            echo "      - MO_ENABLE_V201=0" >> "$OUTPUT_COMPOSE"
        else
            echo "      - MO_ENABLE_V201=1" >> "$OUTPUT_COMPOSE"
            echo "      - BASIC_AUTH_PASSWORD=" >> "$OUTPUT_COMPOSE"
        fi
        
        echo "" >> "$OUTPUT_COMPOSE"
        
        ((index++))
    done < "$charging_stations_file"
    
    log_success "Created Docker Compose file: $OUTPUT_COMPOSE"
}

# =============================================================================
# mo_store generation
# =============================================================================

# =============================================================================
# Template creation, matching generate-simulators.sh
# =============================================================================

create_templates() {
    local templates_dir="./templates"
    
    log_info "Creating or refreshing templates..." >&2
    
    # Create the templates directory.
    mkdir -p "$templates_dir"
    
    # OCPP 1.6 template.
    if [[ -d "./mo_store_v16" ]]; then
        local v16_template_dir="${templates_dir}/mo_store_v16_template"
        rm -rf "$v16_template_dir"
        mkdir -p "$v16_template_dir"
        
        # Copy mo_store_v16 content.
        if [[ ! -f "$v16_template_dir/simulator.jsn" ]]; then
            cp -r "./mo_store_v16"/* "$v16_template_dir/"
        fi
        
        # Create placeholders in template files.
        if [[ -f "${v16_template_dir}/ws-conn.jsn" ]]; then
            sed -i.bak 's|ws://[^/]*/charger-1.6|ws://{{CITRINEOS_IP}}:8081/{{CHARGER_ID}}|g' \
                "${v16_template_dir}/ws-conn.jsn"
            sed -i.bak 's/"charger-1.6"/"{{CHARGER_ID}}"/g' "${v16_template_dir}/ws-conn.jsn"
            rm -f "${v16_template_dir}/ws-conn.jsn.bak"
        fi
        
        if [[ -f "${v16_template_dir}/ocpp-config.jsn" ]]; then
            sed -i.bak 's/"charger-1.6"/"{{CHARGER_ID}}"/g' "${v16_template_dir}/ocpp-config.jsn"
            rm -f "${v16_template_dir}/ocpp-config.jsn.bak"
        fi
    fi
    
    # OCPP 2.0.1 template.
    if [[ -d "./mo_store_v201" ]]; then
        local v201_template_dir="${templates_dir}/mo_store_v201_template"
        rm -rf "$v201_template_dir"
        mkdir -p "$v201_template_dir"
        
        # Copy mo_store_v201 content.
        if [[ ! -f "$v201_template_dir/simulator.jsn" ]]; then
            cp -r "./mo_store_v201"/* "$v201_template_dir/"
        fi
        
        # Create placeholders in template files.
        if [[ -f "${v201_template_dir}/ws-conn-v201.jsn" ]]; then
            sed -i.bak 's|ws://[^/]*/charger-201|ws://{{CITRINEOS_IP}}:8081/{{CHARGER_ID}}|g' \
                "${v201_template_dir}/ws-conn-v201.jsn"
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' \
                "${v201_template_dir}/ws-conn-v201.jsn"
            sed -i.bak 's/"fenexity_test_2025"/"{{AUTH_PASSWORD}}"/g' \
                "${v201_template_dir}/ws-conn-v201.jsn"
            rm -f "${v201_template_dir}/ws-conn-v201.jsn.bak"
        fi
        
        if [[ -f "${v201_template_dir}/ocpp-config.jsn" ]]; then
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' "${v201_template_dir}/ocpp-config.jsn"
            rm -f "${v201_template_dir}/ocpp-config.jsn.bak"
        fi
    fi
    
    log_success "Templates created or updated" >&2
}

generate_mo_store_single() {
    local version="$1"
    local charger_id="$2" 
    local csms_url="$3"
    local auth_password="$4"
    local output_dir="$5"
    
    log_info "Generating mo_store for $charger_id..." >&2
    
    # Resolve the template directory.
    local template_dir
    if [[ "$version" == "1.6" ]]; then
        template_dir="./templates/mo_store_v16_template"
    elif [[ "$version" == "2.0.1" ]]; then
        template_dir="./templates/mo_store_v201_template"
    else
        log_error "Unknown OCPP version: $version"
        return 1
    fi
    
    if [[ ! -d "$template_dir" ]]; then
        log_error "Template directory not found: $template_dir" >&2
        return 1
    fi
    
    # Copy the template files.
    mkdir -p "$output_dir"
    cp -r "${template_dir}"/* "$output_dir/"
    
    # Detect the CitrineOS IP.
    local citrineos_ip
    citrineos_ip=$(detect_citrineos_ip)
    
    if [[ -z "$citrineos_ip" ]]; then
        log_error "Could not determine a valid CitrineOS IP. The container must be running." >&2
        return 1
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
        rm -f "$file.bak"
    done
    
    log_success "Created mo_store for $charger_id: $output_dir" >&2
}

cleanup_old_mo_store() {
    log_info "Cleaning previous mo_store files..."
    
    # Remove the existing mo_store_depot directory if it exists.
    if [[ -d "mo_store_depot" ]]; then
        log_info "Removing the existing mo_store_depot directory..."
        rm -rf mo_store_depot
        log_success "Removed the previous mo_store_depot directory"
    fi
    
    # Create a fresh directory.
    mkdir -p mo_store_depot
    log_success "Created a fresh mo_store_depot directory"
}

ensure_images_exist() {
    local ocpp_version="$1"
    
    log_info "Checking whether the required Docker images exist..."
    
    local image_name
    local ghcr_image
    if [[ "$ocpp_version" == "1.6" ]]; then
        image_name="microocpp-sim-v16:latest"
        ghcr_image="ghcr.io/fenexity/microocpp-sim-v16:latest"
    else
        image_name="microocpp-sim-v201:latest"
        ghcr_image="ghcr.io/fenexity/microocpp-sim-v201:latest"
    fi
    
    # Check whether the image already exists.
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        log_success "Image $image_name is already available"
        return 0
    fi
    
    log_info "Image $image_name not found. Trying to pull it from GHCR..."
    log_info "Pulling image: $ghcr_image"
    echo ""
    
    # Try pulling from GHCR first.
    if docker pull "$ghcr_image" 2>&1; then
        # Tag the GHCR image locally.
        docker tag "$ghcr_image" "$image_name"
        echo ""
        log_success "Pulled $image_name from GHCR successfully"
        log_info "The image is now available locally"
        echo ""
        return 0
    fi
    
    echo ""
    log_warning "GHCR pull failed. Trying a local build..."
    log_info "Building the Docker image for OCPP $ocpp_version..."
    
    # Show basic build information.
    echo "   Dockerfile: Dockerfile"
    echo "   OCPP version: $ocpp_version"
    echo "   Image tag: $image_name"
    echo ""
    
    # Fallback: local build.
    log_info "Starting Docker build. This can take a few minutes..."
    
    if docker build \
        -f Dockerfile \
        --build-arg OCPP_VERSION="$ocpp_version" \
        --build-arg SIMULATOR_PORT=8000 \
        --build-arg CHARGER_ID="depot-charger" \
        --build-arg API_PORT=8000 \
        -t "$image_name" \
        . 2>&1 | while IFS= read -r line; do
            # Show only important build steps.
            if echo "$line" \
                | grep -E "(Step [0-9]+/|Successfully built|Successfully tagged)" \
                    >/dev/null; then
                echo "   $line"
            fi
        done; then
        echo ""
        log_success "Built $image_name successfully"
        log_info "The image is now available for all containers"
        echo ""
    else
        echo ""
        log_error "Failed to build the image $image_name"
        log_error "Possible next steps:"
        echo "   - Run .github/workflows/build-docker-image.yml"
        echo "   - Check Docker: docker info"
        echo "   - Check the Dockerfile: ls -la Dockerfile"
        echo ""
        return 1
    fi
}

generate_mo_store_directories() {
    local charging_stations_file="$1"
    local ocpp_version="$2"
    
    log_info "Generating mo_store directories..." >&2
    
    # Create templates first.
    create_templates
    
    # Recreate the base directory.
    rm -rf "$GENERATED_DIR"
    mkdir -p "$GENERATED_DIR"
    
    local version_key
    if [[ "$ocpp_version" == "1.6" ]]; then
        version_key="v16"
    else
        version_key="v201"
    fi
    
    # Generate mo_store for each charging station.
    local index=1
    while IFS= read -r station_id; do
        local output_dir
        output_dir="${GENERATED_DIR}/depot_${version_key}_$(printf "%03d" $index)"
        
        # Build the CSMS URL from the OCPP version.
        local csms_url
        local auth_password=""
        if [[ "$ocpp_version" == "1.6" ]]; then
            csms_url="ws://citrineos:8081/${station_id}"
        else
            csms_url="ws://citrineos:8081/${station_id}"
        fi
        
        # Reuse the same helper as generate-simulators.sh.
        generate_mo_store_single \
            "$ocpp_version" \
            "$station_id" \
            "$csms_url" \
            "$auth_password" \
            "$output_dir"
        
        ((index++))
    done < "$charging_stations_file"
    
    log_success "Generated all mo_store directories in: $GENERATED_DIR" >&2
}

# =============================================================================
# Batch startup
# =============================================================================

start_containers_in_batches() {
    local compose_file="$1"
    local batch_size=${2:-5}  # Default: 5 containers per batch
    
    log_info "Batch size: $batch_size containers at a time"
    
    # Extract all service names from the Docker Compose file without yq.
    # Ignore the depot-config service.
    local services
    if ! services=$(
        awk '/^services:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && \
            /^  [a-zA-Z0-9_-]+:/ {print $1}' \
            "$compose_file" | sed 's/:$//' | grep -v 'depot-config'
    ); then
        log_error "Failed to extract service names from $compose_file"
        return 1
    fi
    
    local service_count
    service_count=$(echo "$services" | wc -l | tr -d ' ')
    
    if [[ "$service_count" -eq 0 ]]; then
        log_error "No services found in $compose_file."
        return 1
    fi
    
    log_success "Found $service_count services"
    
    # Start the configuration service first.
    log_info "Starting configuration service..."
    if ! docker-compose -f "$compose_file" up -d depot-config 2>/dev/null; then
        log_info "No depot-config service found. Skipping it."
    else
        log_success "depot-config gestartet"
    fi
    
    echo ""
    log_info "Starting containers in batches..."
    
    local current_batch=0
    local services_started=0
    local batch_services=()
    
    while IFS= read -r service_name; do
        batch_services+=("$service_name")
        ((current_batch++))
        
        # Start when the batch is full or the last service is reached.
        if [[ "$current_batch" -eq "$batch_size" ]] \
            || [[ "$services_started" -eq $((service_count - current_batch)) ]]; then
            local batch_number=$(((services_started / batch_size) + 1))
            log_info "Batch $batch_number ($current_batch services):"
            log_info "${batch_services[*]}"
            
            # Start the current batch.
            if ! docker-compose -f "$compose_file" up -d "${batch_services[@]}"; then
                log_error "Failed to start batch $batch_number"
                return 1
            fi
            
            log_success "Started batch $batch_number successfully"
            services_started=$((services_started + current_batch))
            
            # Reset for the next batch.
            batch_services=()
            current_batch=0
            
            # Wait between batches except after the last one.
            if [[ "$services_started" -lt "$service_count" ]]; then
                log_info "Waiting 3 seconds before the next batch..."
                sleep 3
            fi
        fi
    done <<< "$services"
    
    echo ""
    log_success "Batch startup finished"
    echo ""
    echo "Summary:"
    echo "   ✅ Started successfully: $services_started services"
    echo "   Total: $service_count services"
    echo ""
    
    return 0
}

# =============================================================================
# Batch restart
# =============================================================================

restart_containers_in_batches() {
    local compose_file="$1"
    local batch_size=${2:-5}  # Default: 5 containers per batch
    
    log_info "Restarting containers in batches for better CitrineOS detection..."
    log_info "Batch size: $batch_size containers at a time"
    
    # Extract all service names from the Docker Compose file without yq.
    # Ignore the depot-config service.
    local services
    if ! services=$(
        awk '/^services:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && \
            /^  [a-zA-Z0-9_-]+:/ {print $1}' \
            "$compose_file" | sed 's/:$//' | grep -v 'depot-config'
    ); then
        log_error "Failed to extract service names from $compose_file"
        return 1
    fi
    
    local service_count
    service_count=$(echo "$services" | wc -l | tr -d ' ')
    
    if [[ "$service_count" -eq 0 ]]; then
        log_error "No services found in $compose_file."
        return 1
    fi
    
    log_success "Found $service_count services to restart"
    
    echo ""
    log_info "Restarting containers in batches..."
    
    local current_batch=0
    local services_restarted=0
    local batch_services=()
    
    while IFS= read -r service_name; do
        batch_services+=("$service_name")
        ((current_batch++))
        
        # Restart when the batch is full or the last service is reached.
        if [[ "$current_batch" -eq "$batch_size" ]] \
            || [[ "$services_restarted" -eq $((service_count - current_batch)) ]]; then
            local batch_number=$(((services_restarted / batch_size) + 1))
            log_info "Restart batch $batch_number ($current_batch services):"
            log_info "${batch_services[*]}"
            
            # Restart the current batch.
            if ! docker-compose -f "$compose_file" restart "${batch_services[@]}"; then
                log_error "Failed to restart batch $batch_number"
                return 1
            fi
            
            log_success "Restarted batch $batch_number successfully"
            services_restarted=$((services_restarted + current_batch))
            
            # Reset for the next batch.
            batch_services=()
            current_batch=0
            
            # Wait between batches except after the last one.
            if [[ "$services_restarted" -lt "$service_count" ]]; then
                log_info "Waiting 5 seconds before the next restart batch..."
                sleep 5
            fi
        fi
    done <<< "$services"
    
    echo ""
    log_success "Batch restart finished"
    echo ""
    echo "Restart summary:"
    echo "   ✅ Restarted successfully: $services_restarted services"
    echo "   Total: $service_count services"
    echo ""
    
    return 0
}

# =============================================================================
# Main entry point
# =============================================================================

main() {
    echo "MicroOCPP Depot Generator"
    echo "====================================="
    echo ""
    
    # Parse parameters.
    if [[ $# -lt 1 ]]; then
        log_error "A CSV file is required"
        echo ""
        show_help
        exit 1
    fi
    
    CSV_FILE="$1"
    
    # Parse all parameters.
    for arg in "$@"; do
        case $arg in
            --no-start)
                NO_START=true
                shift
                ;;
            1.6|2.0.1)
                OCPP_VERSION="$arg"
                shift
                ;;
        esac
    done
    
    # Show help.
    if [[ "$CSV_FILE" == "-h" || "$CSV_FILE" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    # Update URL mode.
    if [[ "$CSV_FILE" == "--update-url" ]]; then
        log_info "CitrineOS IP update mode enabled"
        
        # Detect the new CitrineOS IP.
        local new_ip
        new_ip=$(detect_citrineos_ip)
        
        if [[ -z "$new_ip" ]]; then
            log_error "Could not determine the CitrineOS IP"
            exit 1
        fi
        
        # Update containers.
        update_citrineos_ip_in_containers "$new_ip"
        
        # Restart containers.
        log_info ""
        restart_depot_containers "all"
        
        log_success "IP update and container restart finished"
        exit 0
    fi
    
    # Validate inputs.
    validate_csv_file "$CSV_FILE" || exit 1
    validate_ocpp_version "$OCPP_VERSION" || exit 1
    
    # Keep the CSV file name for generated comments.
    local csv_filename=$(basename "$CSV_FILE")
    
    log_info "Starting depot generation..."
    log_info "CSV file: $CSV_FILE"
    log_info "OCPP version: $OCPP_VERSION"
    
    # Extract charging stations.
    local charging_stations_file
    charging_stations_file=$(extract_charging_stations "$CSV_FILE")
    local extract_result=$?
    
    if [[ $extract_result -ne 0 || ! -f "$charging_stations_file" ]]; then
        log_error "Failed to extract charger IDs"
        exit 1
    fi
    
    local station_count=$(wc -l < "$charging_stations_file")
    if [[ $station_count -eq 0 ]]; then
        log_error "No valid charger IDs found in the CSV"
        rm -f "$charging_stations_file"
        exit 1
    fi
    
    # Clean previous mo_store files.
    cleanup_old_mo_store
    
    # Ensure the required Docker images exist.
    ensure_images_exist "$OCPP_VERSION"
    
    # Generate configs.
    generate_simulator_config "$charging_stations_file" "$OCPP_VERSION" "$csv_filename"
    generate_docker_compose "$charging_stations_file" "$OCPP_VERSION" "$CSV_FILE"
    generate_mo_store_directories "$charging_stations_file" "$OCPP_VERSION"
    
    echo ""
    log_success "Depot generation finished"
    echo ""
    echo "Generated files:"
    echo "   Configuration: $OUTPUT_CONFIG"
    echo "   Docker Compose: $OUTPUT_COMPOSE"
    echo "   mo_store: $GENERATED_DIR"
    echo ""
    echo "Depot summary:"
    echo "   Depot: $csv_filename"
    echo "   OCPP version: $OCPP_VERSION"
    echo "   Charging stations: $station_count"
    echo ""
    
    # Start containers automatically unless --no-start is set.
    if [[ "$NO_START" == "true" ]]; then
        log_info "Containers were not started (--no-start was set)"
        echo ""
        echo "Next steps:"
        echo "   Start containers: docker-compose -f docker-compose-depot.yml up -d"
        echo "   Check status: docker-compose -f docker-compose-depot.yml ps"
        echo "   Show logs: docker-compose -f docker-compose-depot.yml logs -f"
        echo ""
        echo "Stop:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo ""
        echo "Clean up:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo "   rm -f simulator-config-depot.yml docker-compose-depot.yml"
        echo "   rm -rf mo_store_depot"
    else
        log_info "Starting depot simulators in batches..."
        
        if start_containers_in_batches "$OUTPUT_COMPOSE"; then
        log_success "Containers started successfully"
        echo ""
        
        # Optional restart retained for future tuning.
        # log_info "Waiting 10 seconds before optimized restart..."
        # sleep 10
        
        # if restart_containers_in_batches "$OUTPUT_COMPOSE"; then
        #     log_success "Batch restart finished successfully"
        # else
        #     log_error "Batch restart failed"
        # fi
        # echo ""
        
        # Show container status.
        log_info "Container status:"
        docker-compose -f "$OUTPUT_COMPOSE" ps
        
        echo ""
        log_success "Depot simulators started successfully"
        echo ""
        echo "Next steps:"
        echo "   Open frontend URLs:"
        
        # Build frontend URLs from the generated ports.
        local base_port
        if [[ "$OCPP_VERSION" == "1.6" ]]; then
            base_port=7101
        else
            base_port=7201
        fi
        
        local index=1
        while IFS= read -r station_id; do
            local port=$((base_port + index - 1))
            echo "      http://localhost:$port (ID: $station_id)"
            ((index++))
            if [[ $index -gt 5 ]]; then
                echo "      ... and $((station_count - 5)) more URLs"
                break
            fi
        done < "$charging_stations_file"
        
        echo ""
        echo "   Check status: docker-compose -f docker-compose-depot.yml ps"
        echo "   Show logs: docker-compose -f docker-compose-depot.yml logs -f"
        echo ""
        echo "Stop:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo ""
        echo "Clean up:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo "   rm -f simulator-config-depot.yml docker-compose-depot.yml"
        echo "   rm -rf mo_store_depot"
    else
        log_error "Failed to start containers"
        echo ""
        echo "Manual start:"
        echo "   docker-compose -f docker-compose-depot.yml up -d"
        exit 1
    fi
    fi
    
    # Remove the temporary file at the end.
    rm -f "$charging_stations_file"
}

# Run the main function.
main "$@"
