#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - Depot Starter
# =============================================================================
# Startet Depot-Container in kleineren Batches um Speicherprobleme zu vermeiden
#
# Verwendung:
#   ./start-depot.sh [BATCH_SIZE]
#   ./start-depot.sh 5    # Startet 5 Container gleichzeitig
#   ./start-depot.sh      # Standard: 3 Container gleichzeitig
#
# Voraussetzungen:
#   - docker-compose-depot.yml muss existieren (von generate-depot.sh erstellt)
# =============================================================================

set -e

# =============================================================================
# Konfiguration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-depot.yml"
BATCH_SIZE=${1:-3}  # Standard: 3 Container gleichzeitig

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
    echo "🚀 Fenexity MicroOCPP Depot Starter"
    echo "===================================="
    echo ""
    echo "Startet Depot-Container in kleineren Batches um Speicherprobleme zu vermeiden."
    echo ""
    echo "Verwendung:"
    echo "  $0 [BATCH_SIZE]"
    echo ""
    echo "Parameter:"
    echo "  BATCH_SIZE    Anzahl Container pro Batch (Standard: 3)"
    echo ""
    echo "Beispiele:"
    echo "  $0           # Startet 3 Container gleichzeitig"
    echo "  $0 5         # Startet 5 Container gleichzeitig"
    echo "  $0 1         # Startet Container einzeln (langsamste, aber sicherste Option)"
    echo ""
    echo "Voraussetzungen:"
    echo "  📄 docker-compose-depot.yml (erstellt von generate-depot.sh)"
}

# =============================================================================
# Hauptfunktion
# =============================================================================

main() {
    echo "🚀 Fenexity MicroOCPP Depot Starter"
    echo "===================================="
    echo ""
    
    # Hilfe anzeigen
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    # Validierungen
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker Compose Datei nicht gefunden: $COMPOSE_FILE"
        log_error "Führe zuerst './generate-depot.sh <CSV_FILE> [OCPP_VERSION] --no-start' aus"
        exit 1
    fi
    
    if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || [[ "$BATCH_SIZE" -lt 1 ]]; then
        log_error "BATCH_SIZE muss eine positive Zahl sein: $BATCH_SIZE"
        exit 1
    fi
    
    log_info "Batch-Größe: $BATCH_SIZE Container gleichzeitig"
    log_info "Docker Compose: $COMPOSE_FILE"
    
    # Extrahiere Service-Namen aus docker-compose.yml
    log_info "Extrahiere Service-Namen..."
    local services=($(docker-compose -f "$COMPOSE_FILE" config --services | grep -v "depot-config"))
    local total_services=${#services[@]}
    
    if [[ $total_services -eq 0 ]]; then
        log_error "Keine Services in $COMPOSE_FILE gefunden"
        exit 1
    fi
    
    log_success "Gefunden: $total_services Services"
    log_info "Services: ${services[0]}, ${services[1]}, ... (und $((total_services - 2)) weitere)"
    
    echo ""
    log_info "Starte Container in Batches..."
    
    # Starte depot-config Service zuerst
    log_info "Starte Konfigurations-Service..."
    if docker-compose -f "$COMPOSE_FILE" up -d depot-config; then
        log_success "depot-config gestartet"
    else
        log_warning "depot-config konnte nicht gestartet werden (möglicherweise bereits vorhanden)"
    fi
    
    echo ""
    
    # Starte Services in Batches
    local batch=1
    local started=0
    local failed=0
    
    for ((i=0; i<total_services; i+=BATCH_SIZE)); do
        local batch_services=("${services[@]:$i:$BATCH_SIZE}")
        local batch_count=${#batch_services[@]}
        
        log_info "📦 Batch $batch ($batch_count Services): ${batch_services[*]}"
        
        # Starte aktuellen Batch
        if docker-compose -f "$COMPOSE_FILE" up -d "${batch_services[@]}"; then
            log_success "Batch $batch erfolgreich gestartet"
            ((started += batch_count))
        else
            log_error "Fehler beim Starten von Batch $batch"
            ((failed += batch_count))
        fi
        
        # Kurze Pause zwischen Batches (außer beim letzten)
        if [[ $((i + BATCH_SIZE)) -lt $total_services ]]; then
            log_info "⏳ Warte 3 Sekunden vor nächstem Batch..."
            sleep 3
        fi
        
        ((batch++))
    done
    
    echo ""
    log_success "🎉 Batch-Start abgeschlossen!"
    echo ""
    echo "📊 Zusammenfassung:"
    echo "   ✅ Erfolgreich gestartet: $started Services"
    if [[ $failed -gt 0 ]]; then
        echo "   ❌ Fehlgeschlagen: $failed Services"
    fi
    echo "   📈 Gesamt: $total_services Services"
    
    echo ""
    log_info "Prüfe Container-Status..."
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo "📋 Nützliche Befehle:"
    echo "   📊 Status prüfen: docker-compose -f docker-compose-depot.yml ps"
    echo "   📋 Logs anzeigen: docker-compose -f docker-compose-depot.yml logs -f"
    echo "   🔍 Logs filtern: docker-compose -f docker-compose-depot.yml logs -f depot-sim-v16-001"
    echo ""
    echo "🛑 Stoppen:"
    echo "   docker-compose -f docker-compose-depot.yml down"
    echo ""
    echo "🧹 Bereinigen:"
    echo "   docker-compose -f docker-compose-depot.yml down"
    echo "   rm -f simulator-config-depot.yml docker-compose-depot.yml"
    echo "   rm -rf mo_store_depot"
}

# Führe Hauptfunktion aus
main "$@"
