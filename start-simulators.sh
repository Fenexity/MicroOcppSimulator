#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - One-Command Starter
# =============================================================================
# Kombiniert Generierung und Start in einem einzigen Befehl
#
# Verwendung:
#   ./start-simulators.sh [OPTIONS]
#
# Optionen:
#   --config FILE    Alternative Konfigurationsdatei
#   --clean          Bereinige vorherige Generierungen
#   --logs           Zeige Logs nach dem Start
#   --detach         Starte im Hintergrund (Standard)
#   --foreground     Starte im Vordergrund
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

# Flags
CLEAN_MODE=false
SHOW_LOGS=false
DETACH_MODE=true
CUSTOM_CONFIG=""

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
Verwendung: $0 [OPTIONEN]

One-Command Starter für MicroOCPP Multi-Container Simulatoren.

OPTIONEN:
    --config FILE    Alternative Konfigurationsdatei verwenden
    --clean          Bereinige vorherige Generierungen vor Start
    --logs           Zeige Container-Logs nach dem Start
    --detach         Starte Container im Hintergrund (Standard)
    --foreground     Starte Container im Vordergrund
    -h, --help       Zeige diese Hilfe

BEISPIELE:
    $0                           # Standard-Start
    $0 --clean --logs            # Bereinigen, starten und Logs anzeigen
    $0 --config my-config.yml    # Alternative Konfiguration
    $0 --foreground              # Vordergrund-Modus für Debugging

WORKFLOW:
    1. Liest simulator-config.yml
    2. Führt generate-simulators.sh aus
    3. Startet docker-compose -f docker-compose.generated.yml
    4. Optional: Zeigt Logs oder Status
EOF
                exit 0
                ;;
            *)
                log_error "Unbekannte Option: $1. Verwende --help für Hilfe."
                ;;
        esac
    done
    
    # Verwende custom config falls angegeben
    if [[ -n "$CUSTOM_CONFIG" ]]; then
        if [[ -f "$CUSTOM_CONFIG" ]]; then
            CONFIG_FILE="$CUSTOM_CONFIG"
        else
            log_error "Konfigurationsdatei nicht gefunden: $CUSTOM_CONFIG"
        fi
    fi
}

check_prerequisites() {
    log_info "Prüfe Voraussetzungen..."
    
    # Prüfe ob Konfigurationsdatei existiert
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
    fi
    
    # Prüfe ob Generator-Script existiert
    if [[ ! -f "${SCRIPT_DIR}/generate-simulators.sh" ]]; then
        log_error "Generator-Script nicht gefunden: ${SCRIPT_DIR}/generate-simulators.sh"
    fi
    
    # Prüfe ob Docker verfügbar ist
    if ! command -v docker &> /dev/null; then
        log_error "Docker ist nicht installiert oder nicht verfügbar"
    fi
    
    # Prüfe Docker Compose
    local compose_cmd=""
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    elif command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        log_error "Weder 'docker compose' noch 'docker-compose' verfügbar"
    fi
    
    log_success "Alle Voraussetzungen erfüllt"
}

show_configuration_summary() {
    log_info "Konfigurationsübersicht:"
    echo "   📄 Konfigurationsdatei: $CONFIG_FILE"
    
    # Versuche Konfiguration zu lesen (falls yq verfügbar)
    if command -v yq &> /dev/null; then
        local v16_count=$(yq eval '.simulators.v16.count // 0' "$CONFIG_FILE" 2>/dev/null || echo "?")
        local v201_count=$(yq eval '.simulators.v201.count // 0' "$CONFIG_FILE" 2>/dev/null || echo "?")
        local v16_base_port=$(yq eval '.simulators.v16.base_port // "?"' "$CONFIG_FILE" 2>/dev/null || echo "?")
        local v201_base_port=$(yq eval '.simulators.v201.base_port // "?"' "$CONFIG_FILE" 2>/dev/null || echo "?")
        
        echo "   📊 OCPP 1.6: $v16_count Simulatoren (ab Port $v16_base_port)"
        echo "   📊 OCPP 2.0.1: $v201_count Simulatoren (ab Port $v201_base_port)"
        echo "   📈 Gesamt: $((v16_count + v201_count)) Simulatoren"
    else
        log_warning "yq nicht installiert - überspringe detaillierte Konfigurationsanzeige"
    fi
}

run_generator() {
    log_info "Führe Multi-Container-Generierung aus..."
    
    local generator_args=""
    if [[ "$CLEAN_MODE" == true ]]; then
        generator_args="--clean"
    fi
    
    if [[ -n "$CUSTOM_CONFIG" ]]; then
        generator_args="$generator_args --config $CUSTOM_CONFIG"
    fi
    
    # Führe Generator aus
    bash "${SCRIPT_DIR}/generate-simulators.sh" $generator_args
    
    if [[ $? -eq 0 ]]; then
        log_success "Multi-Container-Generierung abgeschlossen"
    else
        log_error "Multi-Container-Generierung fehlgeschlagen"
    fi
}

start_containers() {
    log_info "Starte Multi-Container-Simulatoren..."
    
    local compose_file="${SCRIPT_DIR}/docker-compose.generated.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Generierte Docker Compose Datei nicht gefunden: $compose_file"
    fi
    
    # Bestimme Docker Compose Command
    local compose_cmd="docker compose"
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        if command -v docker-compose &> /dev/null; then
            compose_cmd="docker-compose"
        else
            log_error "Docker Compose nicht verfügbar"
        fi
    fi
    
    # Starte Container
    local start_args="-f $compose_file up"
    if [[ "$DETACH_MODE" == true ]]; then
        start_args="$start_args -d"
    fi
    
    log_info "Führe aus: $compose_cmd $start_args"
    $compose_cmd $start_args
    
    if [[ $? -eq 0 ]]; then
        log_success "Container erfolgreich gestartet"
    else
        log_error "Container-Start fehlgeschlagen"
    fi
    
    # Zeige Container-Status
    log_info "Container-Status:"
    $compose_cmd -f "$compose_file" ps
}

show_logs() {
    if [[ "$SHOW_LOGS" == true ]]; then
        local compose_file="${SCRIPT_DIR}/docker-compose.generated.yml"
        
        log_info "Zeige Container-Logs (Ctrl+C zum Beenden)..."
        sleep 2
        
        # Bestimme Docker Compose Command
        local compose_cmd="docker compose"
        if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
            compose_cmd="docker-compose"
        fi
        
        $compose_cmd -f "$compose_file" logs -f
    fi
}

print_success_summary() {
    local compose_file="${SCRIPT_DIR}/docker-compose.generated.yml"
    
    echo ""
    log_success "🎉 Multi-Container-Simulatoren erfolgreich gestartet!"
    echo ""
    echo "📋 Nächste Schritte:"
    echo "   🌐 Öffne Frontend-URLs (siehe Ports in der Übersicht)"
    echo "   📊 Status prüfen: docker-compose -f docker-compose.generated.yml ps"
    echo "   📋 Logs anzeigen: docker-compose -f docker-compose.generated.yml logs -f"
    echo "   🛑 Stoppen: docker-compose -f docker-compose.generated.yml down"
    echo "   🧹 Bereinigen: ./cleanup-simulators.sh"
    echo ""
    echo "🔧 Verwaltung:"
    echo "   📝 Konfiguration ändern: nano $CONFIG_FILE"
    echo "   🔄 Neu generieren: ./generate-simulators.sh --clean"
    echo "   🚀 Neu starten: $0 --clean"
    echo ""
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    echo "🚀 Fenexity MicroOCPP One-Command Starter"
    echo "========================================"
    echo ""
    
    # Parse Argumente
    parse_arguments "$@"
    
    # Prüfe Voraussetzungen
    check_prerequisites
    
    # Zeige Konfigurationsübersicht
    show_configuration_summary
    
    echo ""
    
    # Führe Multi-Container-Generierung aus
    run_generator
    
    echo ""
    
    # Starte Container
    start_containers
    
    echo ""
    
    # Zeige Logs (falls gewünscht)
    show_logs
    
    # Erfolgsübersicht (nur im Detach-Modus)
    if [[ "$DETACH_MODE" == true ]]; then
        print_success_summary
    fi
}

# Führe Hauptprogramm aus
main "$@"
