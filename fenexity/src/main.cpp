#include <ArduinoJson.h>

// ... (Weitere Includes) ...

// Environment variable-based configuration
const char* getWebSocketUrl() {
    const char* envUrl = getenv("CENTRAL_SYSTEM_URL");
    if (envUrl) {
        return envUrl;
    }
    return "ws://echo.websocket.events";  // Fallback
}

const char* getChargerId() {
    const char* envId = getenv("CHARGER_ID");
    if (envId) {
        return envId;
    }
    return "charger-01";  // Fallback
}

// ... (Rest der main.cpp mit modifizierten WebSocket-Parametern) ...

int main() {
    // ... (Initialization code) ...
    
    const char* websocketUrl = getWebSocketUrl();
    const char* chargerId = getChargerId();
    
    printf("[Config] WebSocket URL: %s\n", websocketUrl);
    printf("[Config] Charger ID: %s\n", chargerId);
    
    osock = new MicroOcpp::MOcppMongooseClient(&mgr,
        websocketUrl,    // Use environment variable
        chargerId,       // Use environment variable
        "",
        "",
        filesystem,
        g_isOcpp201 ?
            MicroOcpp::ProtocolVersion{2,0,1} :
            MicroOcpp::ProtocolVersion{1,6}
        );
    
    // ... (Rest of the main function) ...
} 