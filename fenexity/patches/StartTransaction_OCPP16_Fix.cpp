// ============================================================================
// Fenexity CSMS Platform - MicroOCPP StartTransaction OCPP 1.6 Compliance Fix
// ============================================================================
// PROBLEM: MicroOCPP-Simulator erstellt eigene Transaction IDs in createConf()
// LÖSUNG: OCPP 1.6-konforme Implementierung ohne eigene Transaction ID Generation
// 
// OCPP 1.6 Standard Flow:
// 1. Charger → CSMS: StartTransaction.req (OHNE transactionId)
// 2. CSMS → Charger: StartTransaction.conf (MIT transactionId vom CSMS)
// 3. Charger nutzt diese transactionId für alle weiteren Nachrichten
//
// Dieses File ersetzt die problematische StartTransaction.cpp der MicroOCPP-Bibliothek

#include <MicroOcpp/Operations/StartTransaction.h>
#include <MicroOcpp/Model/Model.h>
#include <MicroOcpp/Model/Authorization/AuthorizationService.h>
#include <MicroOcpp/Model/Metering/MeteringService.h>
#include <MicroOcpp/Model/Transactions/TransactionStore.h>
#include <MicroOcpp/Model/Transactions/Transaction.h>
#include <MicroOcpp/Debug.h>
#include <MicroOcpp/Version.h>

using MicroOcpp::Ocpp16::StartTransaction;
using MicroOcpp::JsonDoc;

StartTransaction::StartTransaction(Model& model, std::shared_ptr<Transaction> transaction) 
    : MemoryManaged("v16.Operation.", "StartTransaction"), model(model), transaction(transaction) {
    
}

StartTransaction::~StartTransaction() {
    
}

const char* StartTransaction::getOperationType() {
    return "StartTransaction";
}

// ============================================================================
// KORREKTE StartTransaction.req Erstellung (Charger → CSMS)
// WICHTIG: KEINE transactionId im Request! Das ist OCPP 1.6 konform
// ============================================================================
std::unique_ptr<JsonDoc> StartTransaction::createReq() {

    auto doc = makeJsonDoc(getMemoryTag(),
                JSON_OBJECT_SIZE(6) + 
                (IDTAG_LEN_MAX + 1) +
                (JSONDATE_LENGTH + 1));
                
    JsonObject payload = doc->to<JsonObject>();

    // OCPP 1.6 Required Fields für StartTransaction.req
    payload["connectorId"] = transaction->getConnectorId();
    payload["idTag"] = (char*) transaction->getIdTag();
    payload["meterStart"] = transaction->getMeterStart();

    // Optional Fields
    if (transaction->getReservationId() >= 0) {
        payload["reservationId"] = transaction->getReservationId();
    }

    // Timestamp-Handling für Pre-Boot Transactions
    if (transaction->getStartTimestamp() < MIN_TIME &&
            transaction->getStartBootNr() == model.getBootNr()) {
        MO_DBG_DEBUG("[OCPP16_FIX] Adjust preboot StartTx timestamp");
        Timestamp adjusted = model.getClock().adjustPrebootTimestamp(transaction->getStartTimestamp());
        transaction->setStartTimestamp(adjusted);
    }

    char timestamp[JSONDATE_LENGTH + 1] = {'\0'};
    transaction->getStartTimestamp().toJsonString(timestamp, JSONDATE_LENGTH + 1);
    payload["timestamp"] = timestamp;

    MO_DBG_INFO("[OCPP16_FIX] Creating StartTransaction.req WITHOUT transactionId (OCPP 1.6 compliant)");
    
    return doc;
}

// ============================================================================
// KORREKTE StartTransaction.conf Verarbeitung (CSMS → Charger)
// WICHTIG: Transaction ID vom CSMS übernehmen! Das ist OCPP 1.6 konform
// ============================================================================
void StartTransaction::processConf(JsonObject payload) {

    const char* idTagInfoStatus = payload["idTagInfo"]["status"] | "not specified";
    if (!strcmp(idTagInfoStatus, "Accepted")) {
        MO_DBG_INFO("[OCPP16_FIX] StartTransaction request has been ACCEPTED by CSMS");
    } else {
        MO_DBG_INFO("[OCPP16_FIX] StartTransaction request has been DENIED by CSMS. Reason: %s", idTagInfoStatus);
        transaction->setIdTagDeauthorized();
    }

    // ========================================================================
    // KRITISCH: Transaction ID vom CSMS übernehmen (OCPP 1.6 Standard!)
    // ========================================================================
    int transactionId = payload["transactionId"] | -1;
    if (transactionId > 0) {
        transaction->setTransactionId(transactionId);
        MO_DBG_INFO("[OCPP16_FIX] ✅ CSMS provided Transaction ID: %d (OCPP 1.6 compliant)", transactionId);
    } else {
        MO_DBG_ERR("[OCPP16_FIX] ❌ CSMS did not provide valid Transaction ID! This violates OCPP 1.6 standard");
    }

    // Optional: Parent ID Tag verarbeiten
    if (payload["idTagInfo"].containsKey("parentIdTag")) {
        transaction->setParentIdTag(payload["idTagInfo"]["parentIdTag"]);
        MO_DBG_DEBUG("[OCPP16_FIX] Parent ID Tag set: %s", payload["idTagInfo"]["parentIdTag"].as<const char*>());
    }

    // Transaction als bestätigt markieren
    transaction->getStartSync().confirm();
    transaction->commit();

    MO_DBG_INFO("[OCPP16_FIX] Transaction %d successfully started and committed", transactionId);

#if MO_ENABLE_LOCAL_AUTH
    if (auto authService = model.getAuthorizationService()) {
        authService->notifyAuthorization(transaction->getIdTag(), payload["idTagInfo"]);
    }
#endif //MO_ENABLE_LOCAL_AUTH
}

// ============================================================================
// DUMMY processReq (nur für Debug-Zwecke)
// ============================================================================
void StartTransaction::processReq(JsonObject payload) {
    // Ignore Contents of this Req-message, because this is for debug purposes only
    MO_DBG_DEBUG("[OCPP16_FIX] Ignoring incoming StartTransaction.req (debug mode)");
}

// ============================================================================
// KRITISCHER FIX: createConf() ohne eigene Transaction ID Generation
// PROBLEM: Die ursprüngliche Implementierung generierte eigene Transaction IDs
// LÖSUNG: Nur für Debug-Zwecke, KEINE eigene Transaction ID Generation
// ============================================================================
std::unique_ptr<JsonDoc> StartTransaction::createConf() {
    MO_DBG_WARN("[OCPP16_FIX] ⚠️  createConf() called - this should only happen in debug/test mode!");
    MO_DBG_WARN("[OCPP16_FIX] ⚠️  In production, CSMS (CitrineOS) should provide Transaction ID!");
    
    auto doc = makeJsonDoc(getMemoryTag(), JSON_OBJECT_SIZE(1) + JSON_OBJECT_SIZE(2));
    JsonObject payload = doc->to<JsonObject>();

    // Standard OCPP 1.6 Response für Debug-Zwecke
    JsonObject idTagInfo = payload.createNestedObject("idTagInfo");
    idTagInfo["status"] = "Accepted";
    
    // ========================================================================
    // KRITISCHER FIX: KEINE eigene Transaction ID Generation!
    // ========================================================================
    // ORIGINAL PROBLEMATISCHER CODE (ENTFERNT):
    // static int uniqueTxId = 1000;
    // payload["transactionId"] = uniqueTxId++; //sample data for debug purpose
    
    // NEUE LÖSUNG: Fehler-Response für Debug-Modus
    payload["transactionId"] = -1; // Ungültige ID um Problem zu signalisieren
    
    MO_DBG_ERR("[OCPP16_FIX] ❌ DEBUG MODE: Returning invalid transactionId (-1)");
    MO_DBG_ERR("[OCPP16_FIX] ❌ This should NEVER happen in production with real CSMS!");
    MO_DBG_ERR("[OCPP16_FIX] ❌ Configure simulator to connect to CitrineOS instead of using debug mode!");

    return doc;
} 