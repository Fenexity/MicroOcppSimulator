#!/bin/bash
set -e

echo "🔌 MicroOcppSimulator - Team Setup"
echo "=================================="
echo

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funktionen
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
}

# Prüfe Voraussetzungen
check_prerequisites() {
    log_info "Prüfe Voraussetzungen..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker ist nicht installiert!"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose ist nicht installiert!"
        exit 1
    fi
    
    log_success "Alle Voraussetzungen erfüllt"
}

# Hole Git Submodule
init_submodules() {
    log_info "Initialisiere Git Submodule..."
    git submodule update --init --recursive
    log_success "Submodule initialisiert"
}

# Baue Images
build_images() {
    log_info "Baue Docker Images..."
    
    # OCPP 2.0.1 Image
    docker build --platform linux/arm64,linux/amd64 -t microocpp-simulator:v201 .
    
    # OCPP 1.6 Image  
    docker build --platform linux/arm64,linux/amd64 -f Dockerfile.v16 -t microocpp-simulator:v16 .
    
    log_success "Images erfolgreich gebaut"
}

# Zeige verfügbare Optionen
show_menu() {
    echo
    echo "Verfügbare Optionen:"
    echo "1) OCPP 2.0.1 Simulator starten"
    echo "2) OCPP 1.6 Simulator starten"
    echo "3) Beide Simulatoren parallel starten (A/B-Test)"
    echo "4) CitrineOS-Konfiguration anwenden"
    echo "5) Simulator-Status anzeigen"
    echo "6) Logs anzeigen"
    echo "7) Cleanup (alle Container stoppen)"
    echo "0) Beenden"
    echo
}

# Konfiguriere CitrineOS
configure_citrineos() {
    local version=${1:-"201"}
    local port=${2:-"8000"}
    
    log_info "Konfiguriere CitrineOS-Verbindung für OCPP $version..."
    
    # Warte auf Container-Start
    sleep 3
    
    if [ "$version" = "201" ]; then
        curl -X POST "http://localhost:$port/api/websocket" \
            -H "Content-Type: application/json" \
            -d '{
                "backendUrl": "ws://host.docker.internal:8080/ocpp20",
                "chargeBoxId": "charger-simulator-01",
                "authorizationKey": "",
                "pingInterval": 30,
                "reconnectInterval": 10
            }' > /dev/null 2>&1
    else
        curl -X POST "http://localhost:$port/api/websocket" \
            -H "Content-Type: application/json" \
            -d '{
                "backendUrl": "ws://host.docker.internal:8080/ocpp16",
                "chargeBoxId": "charger-simulator-01-v16",
                "authorizationKey": "",
                "pingInterval": 30,
                "reconnectInterval": 10
            }' > /dev/null 2>&1
    fi
    
    log_success "CitrineOS-Konfiguration angewendet"
    log_info "Web-Interface verfügbar unter: http://localhost:$port"
}

# Hauptlogik
main() {
    check_prerequisites
    init_submodules
    
    if [ "$1" = "--build" ]; then
        build_images
    fi
    
    while true; do
        show_menu
        read -p "Wähle eine Option (0-7): " choice
        
        case $choice in
            1)
                log_info "Starte OCPP 2.0.1 Simulator..."
                docker-compose --profile v201 up -d
                configure_citrineos "201" "8000"
                ;;
            2)
                log_info "Starte OCPP 1.6 Simulator..."
                docker-compose --profile v16 up -d
                configure_citrineos "16" "8001"
                ;;
            3)
                log_info "Starte beide Simulatoren..."
                docker-compose --profile dual up -d
                configure_citrineos "201" "8000"
                configure_citrineos "16" "8001"
                log_info "OCPP 2.0.1: http://localhost:8000"
                log_info "OCPP 1.6:   http://localhost:8001"
                ;;
            4)
                log_info "Wende CitrineOS-Konfiguration an..."
                configure_citrineos "201" "8000"
                configure_citrineos "16" "8001"
                ;;
            5)
                docker-compose ps
                ;;
            6)
                echo "Welche Logs? (v201/v16/beide):"
                read log_choice
                case $log_choice in
                    v201) docker-compose logs ocpp-simulator-v201 ;;
                    v16) docker-compose logs ocpp-simulator-v16 ;;
                    *) docker-compose logs ;;
                esac
                ;;
            7)
                log_info "Stoppe alle Simulatoren..."
                docker-compose down
                log_success "Cleanup abgeschlossen"
                ;;
            0)
                log_info "Beende Setup..."
                exit 0
                ;;
            *)
                log_warning "Ungültige Option!"
                ;;
        esac
        
        echo
        read -p "Drücke Enter zum Fortfahren..."
    done
}

# Script ausführen
main "$@" 