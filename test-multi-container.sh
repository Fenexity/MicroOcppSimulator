#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - Multi-Container Test Script
# =============================================================================
# Testet die Multi-Container-Architektur mit verschiedenen Szenarien
#
# Verwendung:
#   ./test-multi-container.sh [SZENARIO]
#
# Szenarien:
#   small     - 2x v16 + 1x v201 (Development)
#   medium    - 5x v16 + 3x v201 (Testing)  
#   large     - 10x v16 + 5x v201 (Load Testing)
#   custom    - Verwende bestehende simulator-config.yml
# =============================================================================

set -e

# =============================================================================
# Konfiguration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/simulator-config.yml"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Hilfsfunktionen
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

# =============================================================================
# Test-Szenarien
# =============================================================================

create_small_config() {
    log_info "Erstelle Small-Konfiguration (2x v16 + 1x v201)..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# =============================================================================
# Small Test Configuration - Development
# =============================================================================

global:
  network_name: "fenexity-csms"
  citrineos_service: "fenexity-citrineos"
  mo_store_base_path: "./mo_store_generated"

simulators:
  v16:
    count: 2
    base_port: 8101
    ocpp_version: "1.6"
    csms_url_template: "ws://citrineos:8092/{charger_id}"
    base_charger_id: "charger-v16"
    container_prefix: "microocpp-sim-v16"
    environment:
      MO_ENABLE_V201: "0"
    
  v201:
    count: 1
    base_port: 8201
    ocpp_version: "2.0.1"
    csms_url_template: "ws://citrineos:8082/{charger_id}"
    base_charger_id: "charger-v201"
    container_prefix: "microocpp-sim-v201"
    auth_password: "fenexity_test_2025"
    environment:
      MO_ENABLE_V201: "1"
      BASIC_AUTH_PASSWORD: "fenexity_test_2025"

templates:
  v16_mo_store: "./mo_store_v16"
  v201_mo_store: "./mo_store_v201"

docker:
  dockerfile: "Dockerfile.arm64"
  platform: "linux/arm64"
  context: "."
  restart_policy: "unless-stopped"
  healthcheck:
    test: '["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000"]'
    interval: "30s"
    timeout: "10s"
    retries: 3
    start_period: "30s"
EOF
}

create_medium_config() {
    log_info "Erstelle Medium-Konfiguration (5x v16 + 3x v201)..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# =============================================================================
# Medium Test Configuration - Testing
# =============================================================================

global:
  network_name: "fenexity-csms"
  citrineos_service: "fenexity-citrineos"
  mo_store_base_path: "./mo_store_generated"

simulators:
  v16:
    count: 5
    base_port: 8101
    ocpp_version: "1.6"
    csms_url_template: "ws://citrineos:8092/{charger_id}"
    base_charger_id: "charger-v16"
    container_prefix: "microocpp-sim-v16"
    environment:
      MO_ENABLE_V201: "0"
    
  v201:
    count: 3
    base_port: 8201
    ocpp_version: "2.0.1"
    csms_url_template: "ws://citrineos:8082/{charger_id}"
    base_charger_id: "charger-v201"
    container_prefix: "microocpp-sim-v201"
    auth_password: "fenexity_test_2025"
    environment:
      MO_ENABLE_V201: "1"
      BASIC_AUTH_PASSWORD: "fenexity_test_2025"

templates:
  v16_mo_store: "./mo_store_v16"
  v201_mo_store: "./mo_store_v201"

docker:
  dockerfile: "Dockerfile.arm64"
  platform: "linux/arm64"
  context: "."
  restart_policy: "unless-stopped"
  healthcheck:
    test: '["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000"]'
    interval: "30s"
    timeout: "10s"
    retries: 3
    start_period: "30s"
EOF
}

create_large_config() {
    log_info "Erstelle Large-Konfiguration (10x v16 + 5x v201)..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# =============================================================================
# Large Test Configuration - Load Testing
# =============================================================================

global:
  network_name: "fenexity-csms"
  citrineos_service: "fenexity-citrineos"
  mo_store_base_path: "./mo_store_generated"

simulators:
  v16:
    count: 10
    base_port: 8101
    ocpp_version: "1.6"
    csms_url_template: "ws://citrineos:8092/{charger_id}"
    base_charger_id: "charger-v16"
    container_prefix: "microocpp-sim-v16"
    environment:
      MO_ENABLE_V201: "0"
    
  v201:
    count: 5
    base_port: 8201
    ocpp_version: "2.0.1"
    csms_url_template: "ws://citrineos:8082/{charger_id}"
    base_charger_id: "charger-v201"
    container_prefix: "microocpp-sim-v201"
    auth_password: "fenexity_test_2025"
    environment:
      MO_ENABLE_V201: "1"
      BASIC_AUTH_PASSWORD: "fenexity_test_2025"

templates:
  v16_mo_store: "./mo_store_v16"
  v201_mo_store: "./mo_store_v201"

docker:
  dockerfile: "Dockerfile.arm64"
  platform: "linux/arm64"
  context: "."
  restart_policy: "unless-stopped"
  healthcheck:
    test: '["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000"]'
    interval: "30s"
    timeout: "10s"
    retries: 3
    start_period: "30s"
EOF
}

# =============================================================================
# Test-Funktionen
# =============================================================================

test_configuration() {
    log_info "Teste Konfiguration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
    fi
    
    # Prüfe ob yq verfügbar ist
    if ! command -v yq &> /dev/null; then
        log_warning "yq nicht installiert - überspringe detaillierte Validierung"
        return 0
    fi
    
    # Validiere YAML
    if ! yq eval '.' "$CONFIG_FILE" > /dev/null 2>&1; then
        log_error "Ungültiges YAML in $CONFIG_FILE"
    fi
    
    # Zeige Konfigurationsübersicht
    local v16_count=$(yq eval '.simulators.v16.count // 0' "$CONFIG_FILE")
    local v201_count=$(yq eval '.simulators.v201.count // 0' "$CONFIG_FILE")
    local total_count=$((v16_count + v201_count))
    
    log_success "Konfiguration gültig:"
    echo "   📊 OCPP 1.6 Simulatoren: $v16_count"
    echo "   📊 OCPP 2.0.1 Simulatoren: $v201_count"
    echo "   📊 Gesamt: $total_count Simulatoren"
}

run_generator() {
    log_info "Führe Generator aus..."
    
    if [[ ! -f "${SCRIPT_DIR}/generate-simulators.sh" ]]; then
        log_error "Generator-Script nicht gefunden: ${SCRIPT_DIR}/generate-simulators.sh"
    fi
    
    # Führe Generator aus
    bash "${SCRIPT_DIR}/generate-simulators.sh" --clean
    
    if [[ $? -eq 0 ]]; then
        log_success "Generator erfolgreich ausgeführt"
    else
        log_error "Generator fehlgeschlagen"
    fi
}

test_docker_compose() {
    log_info "Teste generierte Docker Compose Datei..."
    
    local compose_file="${SCRIPT_DIR}/docker-compose.generated.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Generierte Docker Compose Datei nicht gefunden: $compose_file"
    fi
    
    # Validiere Docker Compose Syntax
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f "$compose_file" config > /dev/null 2>&1; then
            log_success "Docker Compose Syntax gültig"
        else
            log_error "Docker Compose Syntax ungültig"
        fi
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        if docker compose -f "$compose_file" config > /dev/null 2>&1; then
            log_success "Docker Compose Syntax gültig"
        else
            log_error "Docker Compose Syntax ungültig"
        fi
    else
        log_warning "Docker Compose nicht verfügbar - überspringe Syntax-Validierung"
    fi
    
    # Zeige Service-Übersicht
    local service_count=$(grep -c "container_name:" "$compose_file" || echo "0")
    log_info "Generierte Services: $service_count Container"
}

test_mo_store_generation() {
    log_info "Teste mo_store Generierung..."
    
    local generated_dir="${SCRIPT_DIR}/mo_store_generated"
    
    if [[ ! -d "$generated_dir" ]]; then
        log_error "mo_store_generated Verzeichnis nicht gefunden"
    fi
    
    # Zähle generierte mo_store Verzeichnisse
    local store_count=$(find "$generated_dir" -maxdepth 1 -type d -name "sim_*" | wc -l)
    
    if [[ $store_count -gt 0 ]]; then
        log_success "mo_store Verzeichnisse generiert: $store_count"
        
        # Teste ein paar Beispiel-Dateien
        local first_store=$(find "$generated_dir" -maxdepth 1 -type d -name "sim_*" | head -1)
        if [[ -n "$first_store" ]]; then
            if [[ -f "$first_store/ws-conn.jsn" || -f "$first_store/ws-conn-v201.jsn" ]]; then
                log_success "WebSocket-Konfigurationsdateien gefunden"
            else
                log_warning "Keine WebSocket-Konfigurationsdateien in $first_store"
            fi
        fi
    else
        log_error "Keine mo_store Verzeichnisse generiert"
    fi
}

print_test_summary() {
    local scenario="$1"
    
    echo ""
    log_success "Multi-Container Test abgeschlossen!"
    echo ""
    echo "📋 Test-Szenario: $scenario"
    echo "📁 Konfigurationsdatei: $CONFIG_FILE"
    echo "📄 Docker Compose: docker-compose.generated.yml"
    echo "📂 mo_store: mo_store_generated/"
    echo ""
    echo "🚀 Nächste Schritte:"
    echo "   1. docker-compose -f docker-compose.generated.yml up -d"
    echo "   2. docker-compose -f docker-compose.generated.yml ps"
    echo "   3. Teste Frontend-URLs (siehe Ports in docker-compose.generated.yml)"
    echo "   4. ./cleanup-simulators.sh (zum Bereinigen)"
    echo ""
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    local scenario="${1:-small}"
    
    echo "🧪 Fenexity MicroOCPP Multi-Container Test"
    echo "=========================================="
    echo ""
    
    case $scenario in
        small)
            create_small_config
            ;;
        medium)
            create_medium_config
            ;;
        large)
            create_large_config
            ;;
        custom)
            log_info "Verwende bestehende simulator-config.yml"
            ;;
        *)
            log_error "Unbekanntes Szenario: $scenario. Verfügbar: small, medium, large, custom"
            ;;
    esac
    
    # Führe Tests durch
    test_configuration
    run_generator
    test_docker_compose
    test_mo_store_generation
    
    # Zusammenfassung
    print_test_summary "$scenario"
}

# Führe Hauptprogramm aus
main "$@"
