// matth-x/MicroOcpp
// Copyright Matthias Akstaller 2019 - 2024
// MIT License
//
// ============================================================================
// Fenexity CSMS Platform - MicroOCPP StartTransaction OCPP 1.6 Compliance Fix
// ============================================================================
// PROBLEM: Original MicroOCPP creates own Transaction IDs in createConf()
// LÖSUNG: OCPP 1.6-compliant implementation without own Transaction ID Generation
// 
// OCPP 1.6 Standard Flow:
// 1. Charger → CSMS: StartTransaction.req (WITHOUT transactionId)
// 2. CSMS → Charger: StartTransaction.conf (WITH transactionId from CSMS)
// 3. Charger uses this transactionId for all further messages

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


StartTransaction::StartTransaction(Model& model, std::shared_ptr<Transaction> transaction) : MemoryManaged("v16.Operation.", "StartTransaction"), model(model), transaction(transaction) {
    
}

StartTransaction::~StartTransaction() {
    
}

const char* StartTransaction::getOperationType() {
    return "StartTransaction";
}

// ============================================================================
// CORRECT StartTransaction.req Creation (Charger → CSMS)
// IMPORTANT: NO transactionId in Request! This is OCPP 1.6 compliant
// ============================================================================
std::unique_ptr<JsonDoc> StartTransaction::createReq() {

    auto doc = makeJsonDoc(getMemoryTag(),
                JSON_OBJECT_SIZE(6) + 
                (IDTAG_LEN_MAX + 1) +
                (JSONDATE_LENGTH + 1));
                
    JsonObject payload = doc->to<JsonObject>();

    // OCPP 1.6 Required Fields for StartTransaction.req
    payload["connectorId"] = transaction->getConnectorId();
    payload["idTag"] = (char*) transaction->getIdTag();
    payload["meterStart"] = transaction->getMeterStart();

    // Optional Fields
    if (transaction->getReservationId() >= 0) {
        payload["reservationId"] = transaction->getReservationId();
    }

    // Timestamp Handling for Pre-Boot Transactions
    if (transaction->getStartTimestamp() < MIN_TIME &&
            transaction->getStartBootNr() == model.getBootNr()) {
        MO_DBG_DEBUG("[FENEXITY_OCPP16_FIX] Adjust preboot StartTx timestamp");
        Timestamp adjusted = model.getClock().adjustPrebootTimestamp(transaction->getStartTimestamp());
        transaction->setStartTimestamp(adjusted);
    }

    char timestamp[JSONDATE_LENGTH + 1] = {'\0'};
    transaction->getStartTimestamp().toJsonString(timestamp, JSONDATE_LENGTH + 1);
    payload["timestamp"] = timestamp;

    MO_DBG_INFO("[FENEXITY_OCPP16_FIX] Creating StartTransaction.req WITHOUT transactionId (OCPP 1.6 compliant)");
    
    return doc;
}

// ============================================================================
// CORRECT StartTransaction.conf Processing (CSMS → Charger)
// IMPORTANT: Take Transaction ID from CSMS! This is OCPP 1.6 compliant
// ============================================================================
void StartTransaction::processConf(JsonObject payload) {

    const char* idTagInfoStatus = payload["idTagInfo"]["status"] | "not specified";
    if (!strcmp(idTagInfoStatus, "Accepted")) {
        MO_DBG_INFO("[FENEXITY_OCPP16_FIX] StartTransaction request has been ACCEPTED by CSMS");
    } else {
        MO_DBG_INFO("[FENEXITY_OCPP16_FIX] StartTransaction request has been DENIED by CSMS. Reason: %s", idTagInfoStatus);
        transaction->setIdTagDeauthorized();
    }

    // ========================================================================
    // CRITICAL: Take Transaction ID from CSMS (OCPP 1.6 Standard!)
    // ========================================================================
    int transactionId = payload["transactionId"] | -1;
    if (transactionId > 0) {
        transaction->setTransactionId(transactionId);
        MO_DBG_INFO("[FENEXITY_OCPP16_FIX] ✅ CSMS provided Transaction ID: %d (OCPP 1.6 compliant)", transactionId);
    } else {
        MO_DBG_ERR("[FENEXITY_OCPP16_FIX] ❌ CSMS did not provide valid Transaction ID! This violates OCPP 1.6 standard");
    }

    // Optional: Process Parent ID Tag
    if (payload["idTagInfo"].containsKey("parentIdTag")) {
        transaction->setParentIdTag(payload["idTagInfo"]["parentIdTag"]);
        MO_DBG_DEBUG("[FENEXITY_OCPP16_FIX] Parent ID Tag set: %s", payload["idTagInfo"]["parentIdTag"].as<const char*>());
    }

    // Mark Transaction as confirmed
    transaction->getStartSync().confirm();
    transaction->commit();

    MO_DBG_INFO("[FENEXITY_OCPP16_FIX] Transaction %d successfully started and committed", transactionId);

#if MO_ENABLE_LOCAL_AUTH
    if (auto authService = model.getAuthorizationService()) {
        authService->notifyAuthorization(transaction->getIdTag(), payload["idTagInfo"]);
    }
#endif //MO_ENABLE_LOCAL_AUTH
}

// ============================================================================
// DUMMY processReq (only for debug purposes)
// ============================================================================
void StartTransaction::processReq(JsonObject payload) {
    // Ignore Contents of this Req-message, because this is for debug purposes only
    MO_DBG_DEBUG("[FENEXITY_OCPP16_FIX] Ignoring incoming StartTransaction.req (debug mode)");
}

// ============================================================================
// CRITICAL FIX: createConf() without own Transaction ID Generation
// PROBLEM: Original implementation generated own Transaction IDs
// SOLUTION: Only for debug purposes, NO own Transaction ID Generation
// ============================================================================
std::unique_ptr<JsonDoc> StartTransaction::createConf() {
    MO_DBG_WARN("[FENEXITY_OCPP16_FIX] ⚠️  createConf() called - this should only happen in debug/test mode!");
    MO_DBG_WARN("[FENEXITY_OCPP16_FIX] ⚠️  In production, CSMS (CitrineOS) should provide Transaction ID!");
    
    auto doc = makeJsonDoc(getMemoryTag(), JSON_OBJECT_SIZE(1) + JSON_OBJECT_SIZE(2));
    JsonObject payload = doc->to<JsonObject>();

    // Standard OCPP 1.6 Response for debug purposes
    JsonObject idTagInfo = payload.createNestedObject("idTagInfo");
    idTagInfo["status"] = "Accepted";
    
    // ========================================================================
    // CRITICAL FIX: NO own Transaction ID Generation!
    // ========================================================================
    // ORIGINAL PROBLEMATIC CODE (REMOVED):
    // static int uniqueTxId = 1000;
    // payload["transactionId"] = uniqueTxId++; //sample data for debug purpose
    
    // NEW SOLUTION: Error response for debug mode
    payload["transactionId"] = -1; // Invalid ID to signal problem
    
    MO_DBG_ERR("[FENEXITY_OCPP16_FIX] ❌ DEBUG MODE: Returning invalid transactionId (-1)");
    MO_DBG_ERR("[FENEXITY_OCPP16_FIX] ❌ This should NEVER happen in production with real CSMS!");
    MO_DBG_ERR("[FENEXITY_OCPP16_FIX] ❌ Configure simulator to connect to CitrineOS instead of using debug mode!");

    return doc;
}
