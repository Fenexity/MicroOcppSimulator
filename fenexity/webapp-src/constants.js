// Override für MicroOCPP WebApp - Dynamische API-Root basierend auf aktueller URL
// Dies löst das Problem, dass Frontend auf Port 8000 zugreifen will, aber auf 8001/8002 läuft

// Ermittle die aktuelle URL des Browsers und verwende diese als API_ROOT
const getCurrentApiRoot = () => {
    if (typeof window !== 'undefined') {
        // Im Browser: Verwende die aktuelle URL (z.B. http://localhost:8001)
        return `${window.location.protocol}//${window.location.host}`;
    } else {
        // Fallback für Server-Side-Rendering oder Tests
        return process.env.API_ROOT || 'http://localhost:8000';
    }
};

const API_ROOT = getCurrentApiRoot();
const NODE_ENV = process.env.NODE_ENV || 'production';

// Verwendung der ursprünglichen API-Endpunkte aus dem Submodul
const API_ENDPOINT_BACKEND_URL = "/ocpp_backend";
const API_ENDPOINT_EV_STATUS = "/status_ev";
const API_ENDPOINT_EVSE_STATUS = "/status_evse";
const API_ENDPOINT_USER_AUTHORIZATION = "/user_authorization";
const API_ENDPOINT_CERTIFICATE = "/ca_cert";

// API_ROOT wird dynamisch basierend auf der aktuellen Browser-URL gesetzt
// Beispiel: Wenn WebApp auf localhost:8001 läuft, ist API_ROOT = "http://localhost:8001"

export {
	API_ROOT,
	NODE_ENV,
	API_ENDPOINT_BACKEND_URL,
	API_ENDPOINT_EV_STATUS,
	API_ENDPOINT_EVSE_STATUS,
	API_ENDPOINT_USER_AUTHORIZATION,
	API_ENDPOINT_CERTIFICATE
}; 