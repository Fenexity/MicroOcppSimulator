#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - Multi-Container Cleanup
# =============================================================================
# Bereinigt alle generierten Dateien und Container der Multi-Container-Architektur
#
# Verwendung:
#   ./cleanup-simulators.sh [--force] [--containers-only] [--files-only]
#
# Optionen:
#   --force           Keine Bestätigung erforderlich
#   --containers-only Nur Container stoppen/entfernen, Dateien behalten
#   --files-only      Nur Dateien löschen, Container ignorieren
#
# ACHTUNG: Dieses Script entfernt alle generierten Simulatoren unwiderruflich!
# =============================================================================

set -e

# =============================================================================
# Konfiguration und Variablen
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_COMPOSE="${SCRIPT_DIR}/docker-compose.generated.yml"
GENERATED_DIR="${SCRIPT_DIR}/mo_store_generated"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# Farben für Output
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
Verwendung: $0 [OPTIONEN]

Bereinigt alle generierten Multi-Container-Simulatoren.

OPTIONEN:
    --force           Keine Bestätigung erforderlich
    --containers-only Nur Container stoppen/entfernen
    --files-only      Nur Dateien löschen
    -h, --help        Zeige diese Hilfe

BEISPIELE:
    $0                      # Interaktive Bereinigung
    $0 --force              # Vollständige Bereinigung ohne Nachfrage
    $0 --containers-only    # Nur Container stoppen
    $0 --files-only         # Nur generierte Dateien löschen

ACHTUNG: Diese Operation ist unwiderruflich!
EOF
                exit 0
                ;;
            *)
                log_error "Unbekannte Option: $1. Verwende --help für Hilfe."
                ;;
        esac
    done
    
    # Validierung: --containers-only und --files-only schließen sich aus
    if [[ "$CONTAINERS_ONLY" == true && "$FILES_ONLY" == true ]]; then
        log_error "--containers-only und --files-only können nicht gleichzeitig verwendet werden"
    fi
}

confirm_cleanup() {
    if [[ "$FORCE_MODE" == true ]]; then
        return 0
    fi
    
    echo ""
    echo "🚨 ACHTUNG: Multi-Container-Bereinigung"
    echo "======================================="
    echo ""
    
    if [[ "$CONTAINERS_ONLY" == false ]]; then
        echo "📁 Folgende Dateien/Verzeichnisse werden GELÖSCHT:"
        [[ -f "$OUTPUT_COMPOSE" ]] && echo "   • docker-compose.generated.yml"
        [[ -d "$GENERATED_DIR" ]] && echo "   • mo_store_generated/ (alle Simulator-Konfigurationen)"
        echo ""
    fi
    
    if [[ "$FILES_ONLY" == false ]]; then
        echo "🐳 Container-Aktionen:"
        if [[ -f "$OUTPUT_COMPOSE" ]]; then
            echo "   • Alle Multi-Container-Simulatoren werden gestoppt"
            echo "   • Container werden entfernt"
            echo "   • Images bleiben erhalten (können manuell entfernt werden)"
        else
            echo "   • Keine docker-compose.generated.yml gefunden"
        fi
        echo ""
    fi
    
    echo "❓ Möchten Sie fortfahren? (y/N)"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Bereinigung abgebrochen"
        exit 0
    fi
}

stop_containers() {
    if [[ "$FILES_ONLY" == true ]]; then
        log_info "Container-Bereinigung übersprungen (--files-only)"
        return 0
    fi
    
    log_info "Stoppe und entferne Multi-Container-Simulatoren..."
    
    if [[ ! -f "$OUTPUT_COMPOSE" ]]; then
        log_warning "docker-compose.generated.yml nicht gefunden - keine Container zu stoppen"
        return 0
    fi
    
    # Prüfe ob Docker verfügbar ist
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        log_error "Docker/Docker Compose ist nicht verfügbar"
    fi
    
    # Verwende docker compose (neuere Syntax) oder docker-compose (legacy)
    local compose_cmd="docker compose"
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        if command -v docker-compose &> /dev/null; then
            compose_cmd="docker-compose"
        else
            log_error "Weder 'docker compose' noch 'docker-compose' verfügbar"
        fi
    fi
    
    # Stoppe Container
    log_info "Stoppe Container..."
    if $compose_cmd -f "$OUTPUT_COMPOSE" ps -q | grep -q .; then
        $compose_cmd -f "$OUTPUT_COMPOSE" down --remove-orphans
        log_success "Container gestoppt und entfernt"
    else
        log_info "Keine laufenden Container gefunden"
    fi
    
    # Entferne potentiell verwaiste Container
    log_info "Suche nach verwaisten Multi-Container-Simulatoren..."
    local orphaned_containers=$(docker ps -a --filter "name=microocpp-sim-v" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "$orphaned_containers" ]]; then
        log_warning "Gefundene verwaiste Container:"
        echo "$orphaned_containers" | while read -r container; do
            echo "   • $container"
        done
        
        if [[ "$FORCE_MODE" == true ]]; then
            echo "$orphaned_containers" | xargs -r docker rm -f
            log_success "Verwaiste Container entfernt"
        else
            echo ""
            echo "❓ Verwaiste Container entfernen? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "$orphaned_containers" | xargs -r docker rm -f
                log_success "Verwaiste Container entfernt"
            fi
        fi
    else
        log_info "Keine verwaisten Container gefunden"
    fi
}

cleanup_files() {
    if [[ "$CONTAINERS_ONLY" == true ]]; then
        log_info "Datei-Bereinigung übersprungen (--containers-only)"
        return 0
    fi
    
    log_info "Bereinige generierte Dateien..."
    
    local cleaned_files=0
    
    # Entferne Docker Compose Datei
    if [[ -f "$OUTPUT_COMPOSE" ]]; then
        rm "$OUTPUT_COMPOSE"
        log_info "Entfernt: docker-compose.generated.yml"
        cleaned_files=$((cleaned_files + 1))
    fi
    
    # Entferne generierte mo_store Verzeichnisse
    if [[ -d "$GENERATED_DIR" ]]; then
        local store_count=$(find "$GENERATED_DIR" -maxdepth 1 -type d -name "sim_*" | wc -l)
        rm -rf "$GENERATED_DIR"
        log_info "Entfernt: mo_store_generated/ ($store_count Simulator-Konfigurationen)"
        cleaned_files=$((cleaned_files + 1))
    fi
    
    # Optional: Bereinige Template-Cache (nur bei --force)
    if [[ "$FORCE_MODE" == true && -d "$TEMPLATES_DIR" ]]; then
        if [[ -d "${TEMPLATES_DIR}/mo_store_v16_template" || -d "${TEMPLATES_DIR}/mo_store_v201_template" ]]; then
            log_info "Bereinige Template-Cache..."
            rm -rf "${TEMPLATES_DIR}/mo_store_v16_template" "${TEMPLATES_DIR}/mo_store_v201_template" 2>/dev/null || true
            log_info "Template-Cache bereinigt"
            cleaned_files=$((cleaned_files + 1))
        fi
    fi
    
    if [[ $cleaned_files -eq 0 ]]; then
        log_info "Keine Dateien zum Bereinigen gefunden"
    else
        log_success "$cleaned_files Dateien/Verzeichnisse bereinigt"
    fi
}

cleanup_docker_resources() {
    if [[ "$FILES_ONLY" == true || "$FORCE_MODE" == false ]]; then
        return 0
    fi
    
    log_info "Bereinige Docker-Ressourcen..."
    
    # Entferne ungenutzte Images (nur bei --force)
    local unused_images=$(docker images --filter "dangling=true" -q 2>/dev/null || true)
    if [[ -n "$unused_images" ]]; then
        docker rmi $unused_images 2>/dev/null || true
        log_info "Ungenutzte Docker-Images entfernt"
    fi
    
    # Bereinige Docker-Volumes (vorsichtig)
    docker volume prune -f &>/dev/null || true
    log_info "Docker-Volumes bereinigt"
}

print_summary() {
    echo ""
    log_success "Multi-Container-Bereinigung abgeschlossen!"
    echo ""
    echo "📋 Durchgeführte Aktionen:"
    
    if [[ "$FILES_ONLY" == false ]]; then
        echo "   🐳 Container gestoppt und entfernt"
    fi
    
    if [[ "$CONTAINERS_ONLY" == false ]]; then
        echo "   📁 Generierte Dateien gelöscht"
        echo "   🗂️  mo_store-Verzeichnisse bereinigt"
    fi
    
    if [[ "$FORCE_MODE" == true && "$FILES_ONLY" == false ]]; then
        echo "   🧹 Docker-Ressourcen bereinigt"
    fi
    
    echo ""
    echo "🔄 Nächste Schritte:"
    echo "   1. Bearbeite simulator-config.yml nach Bedarf"
    echo "   2. Führe ./generate-simulators.sh aus"
    echo "   3. Starte mit: docker-compose -f docker-compose.generated.yml up -d"
    echo ""
    echo "💡 Tipp: Verwende --containers-only um nur Container zu stoppen,"
    echo "   ohne die Konfigurationsdateien zu löschen."
}

check_running_containers() {
    if [[ ! -f "$OUTPUT_COMPOSE" ]]; then
        return 0
    fi
    
    # Prüfe ob Container aus der generierten Compose-Datei laufen
    local running_containers
    running_containers=$(docker-compose -f "$OUTPUT_COMPOSE" ps -q 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_containers" -gt 0 ]]; then
        log_warning "$running_containers Container aus docker-compose.generated.yml laufen noch"
        echo "   Verwende './cleanup-simulators.sh --containers-only' um sie zu stoppen"
    fi
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    echo "🧹 Fenexity MicroOCPP Multi-Container Cleanup"
    echo "============================================="
    echo ""
    
    # Parse Argumente
    parse_arguments "$@"
    
    # Prüfe aktuelle Situation
    check_running_containers
    
    # Bestätigung einholen
    confirm_cleanup
    
    echo ""
    log_info "Starte Multi-Container-Bereinigung..."
    
    # Stoppe und entferne Container
    stop_containers
    
    # Bereinige Dateien
    cleanup_files
    
    # Bereinige Docker-Ressourcen (nur bei --force)
    cleanup_docker_resources
    
    # Zusammenfassung
    print_summary
}

# Führe Hauptprogramm aus
main "$@"
