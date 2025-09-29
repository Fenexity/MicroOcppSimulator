#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - Depot Generator
# =============================================================================
# Automatische Generierung von OCPP-Simulatoren basierend auf Depot CSV-Dateien
#
# Verwendung:
#   ./generate-depot.sh <CSV_FILE> [OCPP_VERSION]
#   ./generate-depot.sh depot-data/darmstadt-depot.csv 1.6
#   ./generate-depot.sh depot-data/test.csv 2.0.1
#
# Parameter:
#   CSV_FILE      - Pfad zur Depot CSV-Datei
#   OCPP_VERSION  - OCPP Version (1.6 oder 2.0.1, Standard: 1.6)
#
# CSV Format:
#   - Muss eine Spalte "charging_station_id" enthalten
#   - Leere charging_station_id Zeilen werden ignoriert
#   - Eindeutige charging_station_id werden automatisch erkannt
#
# Ausgabe:
#   - simulator-config-depot.yml (generierte Konfiguration)
#   - docker-compose-depot.yml (Docker Compose für Depot)
#   - mo_store_depot/ (Generierte mo_store Verzeichnisse)
# =============================================================================

set -e  # Beende bei Fehlern

# =============================================================================
# Konfiguration und Variablen
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE=""
OCPP_VERSION="1.6"  # Standard
NO_START=false      # Standard: Container automatisch starten
OUTPUT_CONFIG="${SCRIPT_DIR}/simulator-config-depot.yml"
OUTPUT_COMPOSE="${SCRIPT_DIR}/docker-compose-depot.yml"
GENERATED_DIR="${SCRIPT_DIR}/mo_store_depot"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    echo "🔧 Fenexity MicroOCPP Depot Generator"
    echo "====================================="
    echo ""
    echo "Verwendung:"
    echo "  $0 <CSV_FILE> [OCPP_VERSION] [--no-start]"
    echo ""
    echo "Parameter:"
    echo "  CSV_FILE      Pfad zur Depot CSV-Datei (erforderlich)"
    echo "  OCPP_VERSION  OCPP Version: 1.6 oder 2.0.1 (Standard: 1.6)"
    echo "  --no-start    Nur generieren, Container nicht automatisch starten"
    echo ""
    echo "Beispiele:"
    echo "  $0 depot-data/darmstadt-depot.csv"
    echo "  $0 depot-data/test.csv 1.6"
    echo "  $0 depot-data/hamburg.csv 2.0.1 --no-start"
    echo ""
    echo "CSV-Anforderungen:"
    echo "  - Muss Header-Zeile mit 'charging_station_id' Spalte enthalten"
    echo "  - Leere charging_station_id werden ignoriert"
    echo "  - Eindeutige IDs werden automatisch erkannt"
    echo ""
    echo "Ausgabe:"
    echo "  📄 simulator-config-depot.yml"
    echo "  🐳 docker-compose-depot.yml"
    echo "  📁 mo_store_depot/"
}

# =============================================================================
# Validierungsfunktionen
# =============================================================================

validate_csv_file() {
    local csv_file="$1"
    
    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV-Datei nicht gefunden: $csv_file"
        return 1
    fi
    
    # Prüfe ob charging_station_id Spalte existiert
    if ! head -1 "$csv_file" | grep -q "charging_station_id"; then
        log_error "CSV-Datei muss eine 'charging_station_id' Spalte enthalten"
        log_error "Gefundene Header: $(head -1 "$csv_file")"
        return 1
    fi
    
    log_success "CSV-Datei validiert: $csv_file"
    return 0
}

validate_ocpp_version() {
    local version="$1"
    
    if [[ "$version" != "1.6" && "$version" != "2.0.1" ]]; then
        log_error "Ungültige OCPP-Version: $version"
        log_error "Erlaubte Versionen: 1.6, 2.0.1"
        return 1
    fi
    
    log_success "OCPP-Version validiert: $version"
    return 0
}

# =============================================================================
# CSV-Parsing Funktionen
# =============================================================================

extract_charging_stations() {
    local csv_file="$1"
    local temp_file=$(mktemp)
    
    log_info "Extrahiere Ladesäulen-IDs aus CSV..." >&2
    
    # Finde charging_station_id Spalten-Index (berücksichtige Leerzeichen)
    local header=$(head -1 "$csv_file")
    local column_index=$(echo "$header" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -n "charging_station_id" | cut -d: -f1)
    
    if [[ -z "$column_index" ]]; then
        log_error "charging_station_id Spalte nicht gefunden"
        log_error "Header-Zeile: $header"
        log_error "Bereinigte Spalten:"
        echo "$header" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | nl >&2
        rm -f "$temp_file"
        return 1
    fi
    
    log_info "charging_station_id gefunden in Spalte $column_index" >&2
    
    # Extrahiere eindeutige, nicht-leere charging_station_id
    tail -n +2 "$csv_file" | \
        cut -d',' -f"$column_index" | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -v '^$' | \
        sort -u > "$temp_file"
    
    local count=$(wc -l < "$temp_file")
    log_success "Gefunden: $count eindeutige Ladesäulen" >&2
    
    # Zeige erste paar IDs als Vorschau
    if [[ $count -gt 0 ]]; then
        log_info "Beispiel-IDs:" >&2
        head -5 "$temp_file" | sed 's/^/  - /' >&2
        if [[ $count -gt 5 ]]; then
            echo "  ... und $(($count - 5)) weitere" >&2
        fi
    fi
    
    echo "$temp_file"
}

# =============================================================================
# Konfigurationsgenerierung
# =============================================================================

generate_simulator_config() {
    local charging_stations_file="$1"
    local ocpp_version="$2"
    local csv_filename="$3"
    
    log_info "Generiere Simulator-Konfiguration..."
    
    local count=$(wc -l < "$charging_stations_file")
    local version_key
    local base_port
    local csms_url_template
    local env_vars
    
    if [[ "$ocpp_version" == "1.6" ]]; then
        version_key="v16"
        base_port=7101
        csms_url_template="ws://citrineos:8092/{charger_id}"
        env_vars="MO_ENABLE_V201: \"0\""
    else
        version_key="v201"
        base_port=7201
        csms_url_template="ws://citrineos:8081/{charger_id}"
        env_vars="MO_ENABLE_V201: \"1\""
    fi
    
    cat > "$OUTPUT_CONFIG" << EOF
# =============================================================================
# Fenexity MicroOCPP Simulator - Depot Configuration
# =============================================================================
# Automatisch generiert aus: $csv_filename
# OCPP Version: $ocpp_version
# Anzahl Ladesäulen: $count
# Generiert am: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

global:
  network_name: "fenexity-csms"
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
    # Depot-spezifische IDs (werden automatisch zugewiesen)
    depot_ids:
EOF

    # Füge alle charging station IDs hinzu
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

    log_success "Konfiguration erstellt: $OUTPUT_CONFIG"
}


# =============================================================================
# Docker Compose Generierung
# =============================================================================

generate_docker_compose() {
    local charging_stations_file="$1"
    local ocpp_version="$2"
    
    log_info "Generiere Docker Compose Konfiguration..."
    
    local version_key
    local dockerfile="Dockerfile.arm64"
    
    if [[ "$ocpp_version" == "1.6" ]]; then
        version_key="v16"
    else
        version_key="v201"
    fi
    
    # Docker Compose Header
    cat > "$OUTPUT_COMPOSE" << EOF
# =============================================================================
# Fenexity MicroOCPP Simulator - Depot Docker Compose
# =============================================================================
# Automatisch generiert aus Depot CSV
# OCPP Version: $ocpp_version
# Generiert am: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# Docker Compose (version nicht mehr erforderlich)

networks:
  fenexity-csms:
    external: true

services:
  depot-config:
    image: alpine:latest
    container_name: depot-multi-config
    command: >
      sh -c "
        echo '🔧 Starting Depot Multi-Container Configuration...'
        echo '📊 OCPP Version: $ocpp_version'
        echo '📈 Total Simulators: $(wc -l < "$charging_stations_file")'
        echo '🎯 Configuration completed successfully!'
        sleep 5
      "
    networks:
      - fenexity-csms

EOF

    # Generiere Services für jede Ladesäule
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
        
        # Bestimme Image-Name basierend auf OCPP Version
        local image_name
        if [[ "$ocpp_version" == "1.6" ]]; then
            image_name="microocpp-sim-v16:latest"
        else
            image_name="microocpp-sim-v201:latest"
        fi

        cat >> "$OUTPUT_COMPOSE" << EOF
  $service_name:
    image: $image_name
    container_name: $container_name
    platform: linux/arm64
    ports:
      - "$port:8000"
    volumes:
      - "./mo_store_depot/depot_${version_key}_$(printf "%03d" $index):/MicroOcppSimulator/mo_store:rw"
      - "./config:/MicroOcppSimulator/config:ro"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks:
      - fenexity-csms
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
    
    log_success "Docker Compose erstellt: $OUTPUT_COMPOSE"
}

# =============================================================================
# mo_store Generierung
# =============================================================================

# =============================================================================
# Template-Erstellung (exakt wie in generate-simulators.sh)
# =============================================================================

create_templates() {
    local templates_dir="./templates"
    
    log_info "Erstelle/Aktualisiere Templates..." >&2
    
    # Erstelle Templates-Verzeichnis
    mkdir -p "$templates_dir"
    
    # OCPP 1.6 Template
    if [[ -d "./mo_store_v16" ]]; then
        local v16_template_dir="${templates_dir}/mo_store_v16_template"
        rm -rf "$v16_template_dir"
        mkdir -p "$v16_template_dir"
        
        # Kopiere mo_store_v16 Inhalte
        cp -r "./mo_store_v16"/* "$v16_template_dir/"
        
        # Erstelle Platzhalter in Template-Dateien
        if [[ -f "${v16_template_dir}/ws-conn.jsn" ]]; then
            sed -i.bak 's|ws://[^/]*/charger-1.6|ws://{{CITRINEOS_IP}}:8092/{{CHARGER_ID}}|g' "${v16_template_dir}/ws-conn.jsn"
            sed -i.bak 's/"charger-1.6"/"{{CHARGER_ID}}"/g' "${v16_template_dir}/ws-conn.jsn"
            rm -f "${v16_template_dir}/ws-conn.jsn.bak"
        fi
        
        if [[ -f "${v16_template_dir}/ocpp-config.jsn" ]]; then
            sed -i.bak 's/"charger-1.6"/"{{CHARGER_ID}}"/g' "${v16_template_dir}/ocpp-config.jsn"
            rm -f "${v16_template_dir}/ocpp-config.jsn.bak"
        fi
    fi
    
    # OCPP 2.0.1 Template
    if [[ -d "./mo_store_v201" ]]; then
        local v201_template_dir="${templates_dir}/mo_store_v201_template"
        rm -rf "$v201_template_dir"
        mkdir -p "$v201_template_dir"
        
        # Kopiere mo_store_v201 Inhalte
        cp -r "./mo_store_v201"/* "$v201_template_dir/"
        
        # Erstelle Platzhalter in Template-Dateien
        if [[ -f "${v201_template_dir}/ws-conn-v201.jsn" ]]; then
            sed -i.bak 's|ws://[^/]*/charger-201|ws://{{CITRINEOS_IP}}:8081/{{CHARGER_ID}}|g' "${v201_template_dir}/ws-conn-v201.jsn"
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' "${v201_template_dir}/ws-conn-v201.jsn"
            sed -i.bak 's/"fenexity_test_2025"/"{{AUTH_PASSWORD}}"/g' "${v201_template_dir}/ws-conn-v201.jsn"
            rm -f "${v201_template_dir}/ws-conn-v201.jsn.bak"
        fi
        
        if [[ -f "${v201_template_dir}/ocpp-config.jsn" ]]; then
            sed -i.bak 's/"charger-201"/"{{CHARGER_ID}}"/g' "${v201_template_dir}/ocpp-config.jsn"
            rm -f "${v201_template_dir}/ocpp-config.jsn.bak"
        fi
    fi
    
    log_success "Templates erstellt/aktualisiert" >&2
}

generate_mo_store_single() {
    local version="$1"
    local charger_id="$2" 
    local csms_url="$3"
    local auth_password="$4"
    local output_dir="$5"
    
    log_info "Generiere mo_store für $charger_id..." >&2
    
    # Bestimme Template-Verzeichnis
    local template_dir
    if [[ "$version" == "1.6" ]]; then
        template_dir="./templates/mo_store_v16_template"
    elif [[ "$version" == "2.0.1" ]]; then
        template_dir="./templates/mo_store_v201_template"
    else
        log_error "Unbekannte OCPP-Version: $version"
        return 1
    fi
    
    if [[ ! -d "$template_dir" ]]; then
        log_error "Template-Verzeichnis nicht gefunden: $template_dir" >&2
        return 1
    fi
    
    # Kopiere Template-Dateien direkt
    mkdir -p "$output_dir"
    cp -r "${template_dir}"/* "$output_dir/"
    
    # Ermittle CitrineOS IP (wie im original configure-citrineos.sh)
    local citrineos_service="fenexity-citrineos"
    local citrineos_ip
    citrineos_ip=$(docker inspect "$citrineos_service" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
    
    if [[ -z "$citrineos_ip" || "$citrineos_ip" == "null" ]]; then
        log_warning "CitrineOS IP konnte nicht ermittelt werden. Verwende Platzhalter." >&2
        citrineos_ip="172.18.0.3"  # Fallback
    fi
    
    # Erstelle IP-basierte CSMS URL (ersetze Service-Namen mit IP)
    local csms_url_with_ip
    csms_url_with_ip=$(echo "$csms_url" | sed "s/citrineos/$citrineos_ip/g")
    
    # Ersetze Platzhalter in allen JSON-Dateien (exakt wie in generate-simulators.sh)
    find "$output_dir" -name "*.jsn" -o -name "*.json" | while read -r file; do
        sed -i.bak "s/{{CHARGER_ID}}/$charger_id/g" "$file"
        sed -i.bak "s|{{CSMS_URL}}|$csms_url_with_ip|g" "$file"
        sed -i.bak "s/{{AUTH_PASSWORD}}/$auth_password/g" "$file"
        sed -i.bak "s/{{CITRINEOS_IP}}/$citrineos_ip/g" "$file"
        rm -f "$file.bak"
    done
    
    log_success "mo_store für $charger_id erstellt: $output_dir" >&2
}

cleanup_old_mo_store() {
    log_info "Bereinige alte mo_store Dateien..."
    
    # Entferne komplettes mo_store_depot Verzeichnis falls vorhanden
    if [[ -d "mo_store_depot" ]]; then
        log_info "Lösche vorhandenes mo_store_depot Verzeichnis..."
        rm -rf mo_store_depot
        log_success "Altes mo_store_depot Verzeichnis entfernt"
    fi
    
    # Erstelle neues leeres Verzeichnis
    mkdir -p mo_store_depot
    log_success "Neues mo_store_depot Verzeichnis erstellt"
}

ensure_images_exist() {
    local ocpp_version="$1"
    
    log_info "Prüfe ob benötigte Docker Images existieren..."
    
    local image_name
    if [[ "$ocpp_version" == "1.6" ]]; then
        image_name="microocpp-sim-v16:latest"
    else
        image_name="microocpp-sim-v201:latest"
    fi
    
    # Prüfe ob Image existiert
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        log_success "✅ Image $image_name bereits vorhanden"
        return 0
    fi
    
    log_info "🔨 Image $image_name nicht gefunden - starte Build-Prozess..."
    log_info "📦 Baue Docker Image für OCPP $ocpp_version..."
    
    # Zeige Build-Fortschritt
    echo "   🔧 Platform: linux/arm64"
    echo "   📋 Dockerfile: Dockerfile.arm64"
    echo "   🔌 OCPP Version: $ocpp_version"
    echo "   🏷️  Image Tag: $image_name"
    echo ""
    
    # Baue Image mit Standard Build Args (OHNE individuelle API_PORT)
    log_info "⚙️  Starte Docker Build (das kann einige Minuten dauern)..."
    
    if docker build \
        --platform linux/arm64 \
        -f Dockerfile.arm64 \
        --build-arg OCPP_VERSION="$ocpp_version" \
        --build-arg SIMULATOR_PORT=8000 \
        --build-arg CHARGER_ID="depot-charger" \
        --build-arg API_PORT=8000 \
        -t "$image_name" \
        . 2>&1 | while IFS= read -r line; do
            # Zeige nur wichtige Build-Schritte
            if echo "$line" | grep -E "(Step [0-9]+/|Successfully built|Successfully tagged)" >/dev/null; then
                echo "   $line"
            fi
        done; then
        echo ""
        log_success "🎉 Image $image_name erfolgreich erstellt!"
        log_info "💾 Image ist jetzt verfügbar für alle Container"
        echo ""
    else
        echo ""
        log_error "❌ Fehler beim Erstellen des Images $image_name"
        log_error "💡 Mögliche Lösungen:"
        echo "   - Prüfe ob Docker läuft: docker info"
        echo "   - Prüfe ob Dockerfile.arm64 existiert: ls -la Dockerfile.arm64"
        echo "   - Prüfe Docker-Logs: docker system events"
        echo ""
        return 1
    fi
}

generate_mo_store_directories() {
    local charging_stations_file="$1"
    local ocpp_version="$2"
    
    log_info "Generiere mo_store Verzeichnisse..." >&2
    
    # Erstelle Templates zuerst
    create_templates
    
    # Bereinige und erstelle Basis-Verzeichnis
    rm -rf "$GENERATED_DIR"
    mkdir -p "$GENERATED_DIR"
    
    local version_key
    if [[ "$ocpp_version" == "1.6" ]]; then
        version_key="v16"
    else
        version_key="v201"
    fi
    
    # Generiere mo_store für jede Ladesäule
    local index=1
    while IFS= read -r station_id; do
        local output_dir="${GENERATED_DIR}/depot_${version_key}_$(printf "%03d" $index)"
        
        # Erstelle URLs basierend auf OCPP Version
        local csms_url
        local auth_password=""
        if [[ "$ocpp_version" == "1.6" ]]; then
            csms_url="ws://citrineos:8092/${station_id}"
        else
            csms_url="ws://citrineos:8081/${station_id}"
        fi
        
        # Verwende exakt die gleiche Funktion wie generate-simulators.sh
        generate_mo_store_single "$ocpp_version" "$station_id" "$csms_url" "$auth_password" "$output_dir"
        
        ((index++))
    done < "$charging_stations_file"
    
    log_success "Alle mo_store Verzeichnisse generiert in: $GENERATED_DIR" >&2
}

# =============================================================================
# Batch-Start-Funktion
# =============================================================================

start_containers_in_batches() {
    local compose_file="$1"
    local batch_size=${2:-5}  # Standard: 5 Container pro Batch
    
    log_info "Batch-Größe: $batch_size Container gleichzeitig"
    
    # Extrahiere alle Service-Namen aus der Docker Compose Datei (ohne yq)
    # Ignoriere den 'depot-config' Service
    local services
    if ! services=$(awk '/^services:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && /^  [a-zA-Z0-9_-]+:/ {print $1}' "$compose_file" | sed 's/:$//' | grep -v 'depot-config'); then
        log_error "Fehler beim Extrahieren der Service-Namen aus $compose_file"
        return 1
    fi
    
    local service_count
    service_count=$(echo "$services" | wc -l | tr -d ' ')
    
    if [[ "$service_count" -eq 0 ]]; then
        log_error "Keine Services in $compose_file gefunden."
        return 1
    fi
    
    log_success "Gefunden: $service_count Services"
    
    # Starte zuerst den Konfigurationsservice
    log_info "Starte Konfigurations-Service..."
    if ! docker-compose -f "$compose_file" up -d depot-config 2>/dev/null; then
        log_info "Kein depot-config Service gefunden - überspringe"
    else
        log_success "depot-config gestartet"
    fi
    
    echo ""
    log_info "Starte Container in Batches..."
    
    local current_batch=0
    local services_started=0
    local batch_services=()
    
    while IFS= read -r service_name; do
        batch_services+=("$service_name")
        ((current_batch++))
        
        # Wenn Batch voll ist oder letzter Service erreicht
        if [[ "$current_batch" -eq "$batch_size" ]] || [[ "$services_started" -eq $((service_count - current_batch)) ]]; then
            local batch_number=$(((services_started / batch_size) + 1))
            log_info "📦 Batch $batch_number ($current_batch Services): ${batch_services[*]}"
            
            # Starte aktuellen Batch
            if ! docker-compose -f "$compose_file" up -d "${batch_services[@]}"; then
                log_error "Fehler beim Starten von Batch $batch_number"
                return 1
            fi
            
            log_success "Batch $batch_number erfolgreich gestartet"
            services_started=$((services_started + current_batch))
            
            # Reset für nächsten Batch
            batch_services=()
            current_batch=0
            
            # Warte zwischen Batches (außer beim letzten)
            if [[ "$services_started" -lt "$service_count" ]]; then
                log_info "⏳ Warte 3 Sekunden vor nächstem Batch..."
                sleep 3
            fi
        fi
    done <<< "$services"
    
    echo ""
    log_success "🎉 Batch-Start abgeschlossen!"
    echo ""
    echo "📊 Zusammenfassung:"
    echo "   ✅ Erfolgreich gestartet: $services_started Services"
    echo "   📈 Gesamt: $service_count Services"
    echo ""
    
    return 0
}

# =============================================================================
# Batch-Neustart-Funktion
# =============================================================================

restart_containers_in_batches() {
    local compose_file="$1"
    local batch_size=${2:-5}  # Standard: 5 Container pro Batch
    
    log_info "🔄 Starte Batch-Neustart für bessere CitrineOS-Erkennung..."
    log_info "Batch-Größe: $batch_size Container gleichzeitig"
    
    # Extrahiere alle Service-Namen aus der Docker Compose Datei (ohne yq)
    # Ignoriere den 'depot-config' Service
    local services
    if ! services=$(awk '/^services:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && /^  [a-zA-Z0-9_-]+:/ {print $1}' "$compose_file" | sed 's/:$//' | grep -v 'depot-config'); then
        log_error "Fehler beim Extrahieren der Service-Namen aus $compose_file"
        return 1
    fi
    
    local service_count
    service_count=$(echo "$services" | wc -l | tr -d ' ')
    
    if [[ "$service_count" -eq 0 ]]; then
        log_error "Keine Services in $compose_file gefunden."
        return 1
    fi
    
    log_success "Gefunden: $service_count Services für Neustart"
    
    echo ""
    log_info "Starte Container-Neustarts in Batches..."
    
    local current_batch=0
    local services_restarted=0
    local batch_services=()
    
    while IFS= read -r service_name; do
        batch_services+=("$service_name")
        ((current_batch++))
        
        # Wenn Batch voll ist oder letzter Service erreicht
        if [[ "$current_batch" -eq "$batch_size" ]] || [[ "$services_restarted" -eq $((service_count - current_batch)) ]]; then
            local batch_number=$(((services_restarted / batch_size) + 1))
            log_info "🔄 Neustart Batch $batch_number ($current_batch Services): ${batch_services[*]}"
            
            # Starte aktuellen Batch neu
            if ! docker-compose -f "$compose_file" restart "${batch_services[@]}"; then
                log_error "Fehler beim Neustart von Batch $batch_number"
                return 1
            fi
            
            log_success "Batch $batch_number erfolgreich neugestartet"
            services_restarted=$((services_restarted + current_batch))
            
            # Reset für nächsten Batch
            batch_services=()
            current_batch=0
            
            # Warte zwischen Batches (außer beim letzten)
            if [[ "$services_restarted" -lt "$service_count" ]]; then
                log_info "⏳ Warte 5 Sekunden vor nächstem Neustart-Batch..."
                sleep 5
            fi
        fi
    done <<< "$services"
    
    echo ""
    log_success "🎉 Batch-Neustart abgeschlossen!"
    echo ""
    echo "📊 Neustart-Zusammenfassung:"
    echo "   ✅ Erfolgreich neugestartet: $services_restarted Services"
    echo "   📈 Gesamt: $service_count Services"
    echo ""
    
    return 0
}

# =============================================================================
# Hauptfunktion
# =============================================================================

main() {
    echo "🔧 Fenexity MicroOCPP Depot Generator"
    echo "====================================="
    echo ""
    
    # Parameter verarbeiten
    if [[ $# -lt 1 ]]; then
        log_error "CSV-Datei ist erforderlich"
        echo ""
        show_help
        exit 1
    fi
    
    CSV_FILE="$1"
    
    # Parse alle Parameter
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
    
    # Hilfe anzeigen
    if [[ "$CSV_FILE" == "-h" || "$CSV_FILE" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    # Validierungen
    validate_csv_file "$CSV_FILE" || exit 1
    validate_ocpp_version "$OCPP_VERSION" || exit 1
    
    # CSV-Dateinamen für Dokumentation
    local csv_filename=$(basename "$CSV_FILE")
    
    log_info "Starte Depot-Generierung..."
    log_info "📄 CSV-Datei: $CSV_FILE"
    log_info "🔌 OCPP-Version: $OCPP_VERSION"
    
    # Extrahiere Ladesäulen
    local charging_stations_file
    charging_stations_file=$(extract_charging_stations "$CSV_FILE")
    local extract_result=$?
    
    if [[ $extract_result -ne 0 || ! -f "$charging_stations_file" ]]; then
        log_error "Fehler beim Extrahieren der Ladesäulen-IDs"
        exit 1
    fi
    
    local station_count=$(wc -l < "$charging_stations_file")
    if [[ $station_count -eq 0 ]]; then
        log_error "Keine gültigen Ladesäulen-IDs in CSV gefunden"
        rm -f "$charging_stations_file"
        exit 1
    fi
    
    # Bereinige alte mo_store Dateien
    cleanup_old_mo_store
    
    # Stelle sicher, dass benötigte Docker Images existieren
    ensure_images_exist "$OCPP_VERSION"
    
    # Generiere Konfigurationen
    generate_simulator_config "$charging_stations_file" "$OCPP_VERSION" "$csv_filename"
    generate_docker_compose "$charging_stations_file" "$OCPP_VERSION"
    generate_mo_store_directories "$charging_stations_file" "$OCPP_VERSION"
    
    echo ""
    log_success "🎉 Depot-Generierung abgeschlossen!"
    echo ""
    echo "📋 Generierte Dateien:"
    echo "   📄 Konfiguration: $OUTPUT_CONFIG"
    echo "   🐳 Docker Compose: $OUTPUT_COMPOSE"
    echo "   📁 mo_store: $GENERATED_DIR"
    echo ""
    echo "📊 Depot-Übersicht:"
    echo "   🏢 Depot: $csv_filename"
    echo "   🔌 OCPP-Version: $OCPP_VERSION"
    echo "   📈 Ladesäulen: $station_count"
    echo ""
    
    # Starte Container automatisch (falls nicht --no-start gesetzt)
    if [[ "$NO_START" == "true" ]]; then
        log_info "🔧 Container nicht gestartet (--no-start Flag gesetzt)"
        echo ""
        echo "📋 Nächste Schritte:"
        echo "   🚀 Container starten: docker-compose -f docker-compose-depot.yml up -d"
        echo "   📊 Status prüfen: docker-compose -f docker-compose-depot.yml ps"
        echo "   📋 Logs anzeigen: docker-compose -f docker-compose-depot.yml logs -f"
        echo ""
        echo "🛑 Stoppen:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo ""
        echo "🧹 Bereinigen:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo "   rm -f simulator-config-depot.yml docker-compose-depot.yml"
        echo "   rm -rf mo_store_depot"
    else
        log_info "Starte Depot-Simulatoren in Batches..."
        
        if start_containers_in_batches "$OUTPUT_COMPOSE"; then
        log_success "Container erfolgreich gestartet"
        echo ""
        
        # Warte kurz, dann starte alle Container neu für bessere CitrineOS-Erkennung
        log_info "⏳ Warte 10 Sekunden, dann Neustart für CitrineOS-Optimierung..."
        sleep 10
        
        if restart_containers_in_batches "$OUTPUT_COMPOSE"; then
            log_success "Batch-Neustart erfolgreich abgeschlossen"
        else
            log_error "Fehler beim Batch-Neustart"
        fi
        echo ""
        
        # Zeige Container-Status
        log_info "Container-Status:"
        docker-compose -f "$OUTPUT_COMPOSE" ps
        
        echo ""
        log_success "🎉 Depot-Simulatoren erfolgreich gestartet!"
        echo ""
        echo "📋 Nächste Schritte:"
        echo "   🌐 Öffne Frontend-URLs:"
        
        # Generiere Frontend-URLs basierend auf Ports
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
                echo "      ... und $((station_count - 5)) weitere URLs"
                break
            fi
        done < "$charging_stations_file"
        
        echo ""
        echo "   📊 Status prüfen: docker-compose -f docker-compose-depot.yml ps"
        echo "   📋 Logs anzeigen: docker-compose -f docker-compose-depot.yml logs -f"
        echo ""
        echo "🛑 Stoppen:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo ""
        echo "🧹 Bereinigen:"
        echo "   docker-compose -f docker-compose-depot.yml down"
        echo "   rm -f simulator-config-depot.yml docker-compose-depot.yml"
        echo "   rm -rf mo_store_depot"
    else
        log_error "Fehler beim Starten der Container"
        echo ""
        echo "🔧 Manueller Start:"
        echo "   docker-compose -f docker-compose-depot.yml up -d"
        exit 1
    fi
    fi
    
    # Bereinige temporäre Datei am Ende
    rm -f "$charging_stations_file"
}

# Führe Hauptfunktion aus
main "$@"
