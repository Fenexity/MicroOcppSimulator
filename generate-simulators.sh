#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - Multi-Container Generator
# =============================================================================
# Automatische Generierung von Docker Compose Konfiguration und mo_store
# Verzeichnissen basierend auf simulator-config.yml
#
# Verwendung:
#   ./generate-simulators.sh [--clean] [--config CONFIG_FILE]
#
# Optionen:
#   --clean       Bereinige vorherige Generierungen vor der Erstellung
#   --config      Verwende alternative Konfigurationsdatei (Standard: simulator-config.yml)
#
# Ausgabe:
#   - docker-compose.generated.yml
#   - mo_store_generated/sim_*/ Verzeichnisse
#   - Aktualisierte Templates
# =============================================================================

set -e  # Beende bei Fehlern

# =============================================================================
# Konfiguration und Variablen
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/simulator-config.yml"
OUTPUT_COMPOSE="${SCRIPT_DIR}/docker-compose.generated.yml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
GENERATED_DIR="${SCRIPT_DIR}/mo_store_generated"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
CLEAN_MODE=false
VERBOSE=false

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

check_dependencies() {
    log_info "Überprüfe Abhängigkeiten..."
    
    # Prüfe ob yq installiert ist (für YAML-Parsing)
    if ! command -v yq &> /dev/null; then
        log_error "yq ist nicht installiert. Installiere es mit: brew install yq (macOS) oder apt-get install yq (Ubuntu)"
    fi
    
    # Prüfe ob Docker verfügbar ist
    if ! command -v docker &> /dev/null; then
        log_error "Docker ist nicht installiert oder nicht verfügbar"
    fi
    
    log_success "Alle Abhängigkeiten verfügbar"
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
Verwendung: $0 [OPTIONEN]

Generiert Docker Compose Konfiguration für mehrere OCPP-Simulatoren.

OPTIONEN:
    --clean         Bereinige vorherige Generierungen
    --config FILE   Verwende alternative Konfigurationsdatei
    --verbose       Detaillierte Ausgabe
    -h, --help      Zeige diese Hilfe

BEISPIELE:
    $0                              # Standardkonfiguration verwenden
    $0 --clean                      # Bereinigen und neu generieren
    $0 --config custom-config.yml   # Alternative Konfiguration
EOF
                exit 0
                ;;
            *)
                log_error "Unbekannte Option: $1. Verwende --help für Hilfe."
                ;;
        esac
    done
}

validate_config() {
    log_info "Validiere Konfigurationsdatei: $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
    fi
    
    # Prüfe grundlegende YAML-Struktur
    if ! yq eval '.simulators' "$CONFIG_FILE" > /dev/null 2>&1; then
        log_error "Ungültige YAML-Struktur in Konfigurationsdatei"
    fi
    
    # Prüfe ob mindestens eine Simulator-Konfiguration existiert
    local simulator_count=$(yq eval '.simulators | keys | length' "$CONFIG_FILE")
    if [[ "$simulator_count" -eq 0 ]]; then
        log_error "Keine Simulator-Konfigurationen in $CONFIG_FILE gefunden"
    fi
    
    log_success "Konfigurationsdatei ist gültig"
}

cleanup_previous() {
    if [[ "$CLEAN_MODE" == true ]]; then
        log_info "Bereinige vorherige Generierungen..."
        
        # Entferne generierte Docker Compose Datei
        if [[ -f "$OUTPUT_COMPOSE" ]]; then
            rm "$OUTPUT_COMPOSE"
            log_info "Entfernt: docker-compose.generated.yml"
        fi
        
        # Entferne generierte mo_store Verzeichnisse
        if [[ -d "$GENERATED_DIR" ]]; then
            rm -rf "$GENERATED_DIR"
            log_info "Entfernt: mo_store_generated/"
        fi
        
        log_success "Bereinigung abgeschlossen"
    fi
}

create_templates() {
    log_info "Erstelle/Aktualisiere Templates..."
    
    mkdir -p "$TEMPLATES_DIR"
    
    # Erstelle OCPP 1.6 Template
    if [[ -d "${SCRIPT_DIR}/mo_store_v16" ]]; then
        log_info "Erstelle OCPP 1.6 Template aus mo_store_v16/"
        cp -r "${SCRIPT_DIR}/mo_store_v16" "${TEMPLATES_DIR}/mo_store_v16_template"
        
        # Ersetze spezifische Werte durch Platzhalter in ws-conn.jsn
        if [[ -f "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn" ]]; then
            sed -i.bak 's/"charger-1\.6"/"{{CHARGER_ID}}"/g' "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn"
            sed -i.bak 's|ws://[^/]*/charger-1\.6|ws://{{CITRINEOS_IP}}:8092/{{CHARGER_ID}}|g' "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn"
            rm "${TEMPLATES_DIR}/mo_store_v16_template/ws-conn.jsn.bak"
        fi
    else
        log_warning "mo_store_v16/ nicht gefunden - OCPP 1.6 Template wird nicht erstellt"
    fi
    
    # Erstelle OCPP 2.0.1 Template
    if [[ -d "${SCRIPT_DIR}/mo_store_v201" ]]; then
        log_info "Erstelle OCPP 2.0.1 Template aus mo_store_v201/"
        cp -r "${SCRIPT_DIR}/mo_store_v201" "${TEMPLATES_DIR}/mo_store_v201_template"
        
        # Ersetze spezifische Werte durch Platzhalter in ws-conn-v201.jsn
        if [[ -f "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn" ]]; then
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn"
            sed -i.bak 's|ws://[^/]*/charger-201|ws://{{CITRINEOS_IP}}:8082/{{CHARGER_ID}}|g' "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn"
            sed -i.bak 's/"fenexity_test_2025"/"{{AUTH_PASSWORD}}"/g' "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn"
            rm "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn-v201.jsn.bak"
        fi
        
        # Ersetze Werte in ws-conn.jsn (Legacy-Format)
        if [[ -f "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn" ]]; then
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn"
            sed -i.bak 's|ws://[^/]*/charger-201|ws://{{CITRINEOS_IP}}:8082/{{CHARGER_ID}}|g' "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn"
            sed -i.bak 's/"fenexity_test_2025"/"{{AUTH_PASSWORD}}"/g' "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn"
            rm "${TEMPLATES_DIR}/mo_store_v201_template/ws-conn.jsn.bak"
        fi
    else
        log_warning "mo_store_v201/ nicht gefunden - OCPP 2.0.1 Template wird nicht erstellt"
    fi
    
    log_success "Templates erstellt/aktualisiert"
}

generate_mo_store() {
    local version="$1"
    local charger_id="$2"
    local csms_url="$3"
    local auth_password="$4"
    local output_dir="$5"
    
    log_info "Generiere mo_store für $charger_id..."
    
    # Bestimme Template-Verzeichnis
    local template_dir
    if [[ "$version" == "1.6" ]]; then
        template_dir="${TEMPLATES_DIR}/mo_store_v16_template"
    elif [[ "$version" == "2.0.1" ]]; then
        template_dir="${TEMPLATES_DIR}/mo_store_v201_template"
    else
        log_error "Unbekannte OCPP-Version: $version"
    fi
    
    if [[ ! -d "$template_dir" ]]; then
        log_error "Template-Verzeichnis nicht gefunden: $template_dir"
    fi
    
    # Kopiere Template-Dateien direkt
    mkdir -p "$output_dir"
    cp -r "${template_dir}"/* "$output_dir/"
    
    # Ermittle CitrineOS IP (wie im original configure-citrineos.sh)
    local citrineos_service=$(yq eval '.global.citrineos_service // "fenexity-citrineos"' "$CONFIG_FILE")
    local citrineos_ip
    citrineos_ip=$(docker inspect "$citrineos_service" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
    
    if [[ -z "$citrineos_ip" || "$citrineos_ip" == "null" ]]; then
        log_warning "CitrineOS IP konnte nicht ermittelt werden. Verwende Platzhalter."
        citrineos_ip="{{CITRINEOS_IP}}"
    fi
    
    # Erstelle IP-basierte CSMS URL (ersetze Service-Name mit IP)
    local csms_url_with_ip
    csms_url_with_ip=$(echo "$csms_url" | sed "s/citrineos/$citrineos_ip/g")
    
    # Ersetze Platzhalter in allen JSON-Dateien
    find "$output_dir" -name "*.jsn" -o -name "*.json" | while read -r file; do
        sed -i.bak "s/{{CHARGER_ID}}/$charger_id/g" "$file"
        sed -i.bak "s|{{CSMS_URL}}|$csms_url_with_ip|g" "$file"
        sed -i.bak "s/{{AUTH_PASSWORD}}/$auth_password/g" "$file"
        sed -i.bak "s/{{CITRINEOS_IP}}/$citrineos_ip/g" "$file"
        rm "$file.bak"
    done
    
    log_success "mo_store für $charger_id erstellt: $output_dir"
}

generate_docker_compose() {
    log_info "Generiere Docker Compose Konfiguration..."
    
    # Header der Docker Compose Datei
    cat > "$OUTPUT_COMPOSE" << 'EOF'
# =============================================================================
# Fenexity MicroOCPP Simulator - Generierte Multi-Container Konfiguration
# =============================================================================
# ACHTUNG: Diese Datei wurde automatisch generiert!
# Änderungen hier werden beim nächsten Aufruf von generate-simulators.sh überschrieben.
# 
# Für Konfigurationsänderungen bearbeite: simulator-config.yml
# Dann führe aus: ./generate-simulators.sh
# =============================================================================

EOF

    # Netzwerk-Konfiguration
    local network_name=$(yq eval '.global.network_name // "fenexity-csms"' "$CONFIG_FILE")
    cat >> "$OUTPUT_COMPOSE" << EOF
networks:
  default:
    driver: bridge
    name: $network_name
    external: true

services:
EOF

    # Konfiguration Service (für CitrineOS IP-Ermittlung)
    cat >> "$OUTPUT_COMPOSE" << 'EOF'
  # =============================================================================
  # Konfiguration Service (läuft vor Simulator-Start)
  # =============================================================================
  microocpp-multi-config:
    image: alpine:latest
    container_name: microocpp-multi-config
    platform: linux/arm64
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./configure-citrineos.sh:/configure-citrineos.sh:ro
EOF

    # Füge mo_store Volume-Mounts für Konfiguration Service hinzu
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

    # Konfiguration Service Command
    cat >> "$OUTPUT_COMPOSE" << 'EOF'
    command: >
      sh -c "
      echo '🔧 Starte Multi-Simulator-Konfiguration...';
      apk add --no-cache bash grep curl docker-cli;
      echo '✅ Multi-Simulator-Konfiguration abgeschlossen!';
      "
    restart: "no"

EOF

    # Generiere Services für alle Simulator-Versionen
    while IFS= read -r version; do
        generate_simulator_services "$version"
    done <<< "$simulator_versions"

    log_success "Docker Compose Konfiguration erstellt: $OUTPUT_COMPOSE"
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
    
    log_info "Generiere $count Simulatoren für OCPP $ocpp_version..."
    
    # Header für diese Version
    cat >> "$OUTPUT_COMPOSE" << EOF
  # =============================================================================
  # OCPP $ocpp_version Simulatoren ($count Container)
  # =============================================================================
EOF

    # Generiere jeden Simulator
    for ((i=1; i<=count; i++)); do
        local sim_id=$(printf "%03d" $i)
        local charger_id="${base_charger_id}-${sim_id}"
        local port=$((base_port + i - 1))
        local container_name="${container_prefix}-${sim_id}"
        local csms_url="${csms_url_template/\{charger_id\}/$charger_id}"
        local mo_store_path="./mo_store_generated/sim_${version}_${sim_id}"
        
        # Erstelle mo_store für diesen Simulator
        mkdir -p "$GENERATED_DIR"
        generate_mo_store "$ocpp_version" "$charger_id" "$csms_url" "$auth_password" "${GENERATED_DIR}/sim_${version}_${sim_id}"
        
        # Docker Service Definition
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

        # Füge zusätzliche Umgebungsvariablen hinzu
        local env_vars=$(yq eval ".simulators.${version}.environment // {}" "$CONFIG_FILE")
        if [[ "$env_vars" != "null" && "$env_vars" != "{}" ]]; then
            yq eval ".simulators.${version}.environment | to_entries | .[] | \"      - \" + .key + \"=\" + .value" "$CONFIG_FILE" >> "$OUTPUT_COMPOSE"
        fi

        # Service-Konfiguration abschließen
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
    log_success "Multi-Container-Generierung abgeschlossen!"
    echo ""
    echo "📋 Generierte Dateien:"
    echo "   📄 Docker Compose: $OUTPUT_COMPOSE"
    echo "   📁 mo_store Verzeichnisse: $GENERATED_DIR/"
    echo ""
    echo "📊 Simulator-Übersicht:"
    
    local simulator_versions=$(yq eval '.simulators | keys | .[]' "$CONFIG_FILE")
    local total_simulators=0
    
    while IFS= read -r version; do
        local count=$(yq eval ".simulators.${version}.count" "$CONFIG_FILE")
        local base_port=$(yq eval ".simulators.${version}.base_port" "$CONFIG_FILE")
        local ocpp_version=$(yq eval ".simulators.${version}.ocpp_version" "$CONFIG_FILE")
        
        echo "   🔌 OCPP $ocpp_version: $count Simulatoren (Ports $base_port-$((base_port + count - 1)))"
        total_simulators=$((total_simulators + count))
    done <<< "$simulator_versions"
    
    echo "   📈 Gesamt: $total_simulators Simulatoren"
    echo ""
    echo "🚀 Nächste Schritte:"
    echo "   1. docker-compose -f docker-compose.generated.yml up -d"
    echo "   2. Warte auf Container-Start (Health-Checks)"
    echo "   3. Öffne Frontend: http://localhost:[PORT] für jeden Simulator"
    echo ""
    echo "🛠️  Verwaltung:"
    echo "   • Stoppen: docker-compose -f docker-compose.generated.yml down"
    echo "   • Logs: docker-compose -f docker-compose.generated.yml logs -f [service]"
    echo "   • Bereinigen: ./cleanup-simulators.sh"
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    echo "🔧 Fenexity MicroOCPP Multi-Container Generator"
    echo "============================================="
    echo ""
    
    # Parse Argumente
    parse_arguments "$@"
    
    # Prüfe Abhängigkeiten
    check_dependencies
    
    # Validiere Konfiguration
    validate_config
    
    # Bereinige vorherige Generierungen
    cleanup_previous
    
    # Erstelle/Aktualisiere Templates
    create_templates
    
    # Generiere Docker Compose Konfiguration
    generate_docker_compose
    
    # Zusammenfassung ausgeben
    print_summary
}

# Führe Hauptprogramm aus
main "$@"
