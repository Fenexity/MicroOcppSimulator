#!/bin/bash

# =============================================================================
# Fenexity MicroOCPP Simulator - Charger Status Updater
# =============================================================================
# Markiert alle Multi-Container-Simulatoren als online in CitrineOS
#
# Verwendung:
#   ./update-charger-status.sh [--all] [--v16] [--v201] [--charger-id ID]
#
# Optionen:
#   --all         Alle Multi-Container-Charger als online markieren
#   --v16         Nur OCPP 1.6 Charger
#   --v201        Nur OCPP 2.0.1 Charger
#   --charger-id  Spezifische Charger-ID
# =============================================================================

set -e

# =============================================================================
# Konfiguration
# =============================================================================

POSTGRES_CONTAINER="fenexity-postgres"
POSTGRES_USER="citrine"
POSTGRES_DB="citrine"

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

check_prerequisites() {
    log_info "Prüfe Voraussetzungen..."
    
    # Prüfe ob PostgreSQL Container läuft
    if ! docker ps --filter "name=$POSTGRES_CONTAINER" --format "{{.Names}}" | grep -q "$POSTGRES_CONTAINER"; then
        log_error "PostgreSQL Container '$POSTGRES_CONTAINER' läuft nicht"
    fi
    
    log_success "PostgreSQL Container verfügbar"
}

execute_sql() {
    local sql_query="$1"
    local description="$2"
    
    log_info "$description"
    
    local result
    result=$(docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "$sql_query" 2>/dev/null | tr -d ' ')
    
    if [[ $? -eq 0 ]]; then
        echo "$result"
    else
        log_error "SQL-Ausführung fehlgeschlagen: $sql_query"
    fi
}

show_current_status() {
    log_info "Aktueller Charger-Status:"
    
    local query="SELECT id, \"isOnline\", protocol, \"createdAt\" FROM \"ChargingStations\" WHERE id LIKE 'charger-v%' ORDER BY \"createdAt\" DESC;"
    
    docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$query" 2>/dev/null || log_warning "Konnte Status nicht abrufen"
}

update_chargers() {
    local pattern="$1"
    local protocol="$2"
    local description="$3"
    
    local update_query="UPDATE \"ChargingStations\" SET \"isOnline\" = true, protocol = '$protocol' WHERE id LIKE '$pattern';"
    local count_query="SELECT COUNT(*) FROM \"ChargingStations\" WHERE id LIKE '$pattern';"
    
    # Prüfe wie viele Charger betroffen sind
    local count
    count=$(execute_sql "$count_query" "Zähle betroffene Charger...")
    
    if [[ "$count" -eq 0 ]]; then
        log_warning "Keine Charger gefunden für Pattern: $pattern"
        return 0
    fi
    
    log_info "$description ($count Charger gefunden)"
    
    # Führe Update aus
    local updated
    updated=$(execute_sql "$update_query" "Aktualisiere Charger-Status...")
    
    if [[ "$updated" =~ UPDATE.* ]]; then
        log_success "$description abgeschlossen"
        return 0
    else
        log_error "Update fehlgeschlagen für: $pattern"
    fi
}

update_specific_charger() {
    local charger_id="$1"
    
    # Ermittle OCPP-Version basierend auf Charger-ID
    local protocol
    if [[ "$charger_id" =~ v16 ]]; then
        protocol="ocpp1.6"
    elif [[ "$charger_id" =~ v201 ]]; then
        protocol="ocpp2.0.1"
    else
        log_warning "Konnte OCPP-Version für '$charger_id' nicht ermitteln. Verwende 'unknown'"
        protocol="unknown"
    fi
    
    local update_query="UPDATE \"ChargingStations\" SET \"isOnline\" = true, protocol = '$protocol' WHERE id = '$charger_id';"
    local check_query="SELECT COUNT(*) FROM \"ChargingStations\" WHERE id = '$charger_id';"
    
    # Prüfe ob Charger existiert
    local exists
    exists=$(execute_sql "$check_query" "Prüfe ob Charger '$charger_id' existiert...")
    
    if [[ "$exists" -eq 0 ]]; then
        log_error "Charger '$charger_id' nicht in der Datenbank gefunden"
    fi
    
    # Führe Update aus
    execute_sql "$update_query" "Aktualisiere Charger '$charger_id'..."
    log_success "Charger '$charger_id' als online markiert (Protokoll: $protocol)"
}

# =============================================================================
# Hauptfunktionen
# =============================================================================

update_all_chargers() {
    log_info "Markiere alle Multi-Container-Charger als online..."
    
    # OCPP 1.6 Charger
    update_chargers "charger-v16%" "ocpp1.6" "OCPP 1.6 Charger"
    
    # OCPP 2.0.1 Charger
    update_chargers "charger-v201%" "ocpp2.0.1" "OCPP 2.0.1 Charger"
    
    log_success "Alle Multi-Container-Charger aktualisiert"
}

update_v16_chargers() {
    log_info "Markiere OCPP 1.6 Charger als online..."
    update_chargers "charger-v16%" "ocpp1.6" "OCPP 1.6 Charger"
}

update_v201_chargers() {
    log_info "Markiere OCPP 2.0.1 Charger als online..."
    update_chargers "charger-v201%" "ocpp2.0.1" "OCPP 2.0.1 Charger"
}

print_usage() {
    cat << EOF
Verwendung: $0 [OPTIONEN]

Markiert Multi-Container-Simulatoren als online in CitrineOS.

OPTIONEN:
    --all             Alle Multi-Container-Charger (Standard)
    --v16             Nur OCPP 1.6 Charger
    --v201            Nur OCPP 2.0.1 Charger
    --charger-id ID   Spezifische Charger-ID
    --status          Zeige aktuellen Status
    -h, --help        Zeige diese Hilfe

BEISPIELE:
    $0                                    # Alle Multi-Container-Charger
    $0 --v16                              # Nur OCPP 1.6 Charger
    $0 --charger-id charger-v16-003       # Spezifischer Charger
    $0 --status                           # Aktuellen Status anzeigen

HINWEIS:
    Dieses Script markiert Charger nur als online, wenn sie bereits in der
    CitrineOS-Datenbank registriert sind (durch BootNotification).
EOF
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    echo "🔧 Fenexity MicroOCPP Charger Status Updater"
    echo "============================================="
    echo ""
    
    # Parse Argumente
    local action="all"
    local charger_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                action="all"
                shift
                ;;
            --v16)
                action="v16"
                shift
                ;;
            --v201)
                action="v201"
                shift
                ;;
            --charger-id)
                action="specific"
                charger_id="$2"
                shift 2
                ;;
            --status)
                action="status"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unbekannte Option: $1. Verwende --help für Hilfe."
                ;;
        esac
    done
    
    # Prüfe Voraussetzungen
    check_prerequisites
    
    echo ""
    
    # Zeige aktuellen Status
    if [[ "$action" != "status" ]]; then
        show_current_status
        echo ""
    fi
    
    # Führe gewünschte Aktion aus
    case $action in
        all)
            update_all_chargers
            ;;
        v16)
            update_v16_chargers
            ;;
        v201)
            update_v201_chargers
            ;;
        specific)
            if [[ -z "$charger_id" ]]; then
                log_error "Charger-ID ist erforderlich für --charger-id"
            fi
            update_specific_charger "$charger_id"
            ;;
        status)
            # Status wurde bereits oben angezeigt
            ;;
    esac
    
    echo ""
    
    # Zeige finalen Status
    if [[ "$action" != "status" ]]; then
        log_info "Finaler Status nach Update:"
        show_current_status
    fi
    
    echo ""
    log_success "Charger Status Update abgeschlossen!"
}

# Führe Hauptprogramm aus
main "$@"
