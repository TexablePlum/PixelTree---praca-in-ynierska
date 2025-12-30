/*
 * LEDApi.h - HTTP REST API for LED Control
 * 
 * Exposes LED control endpoints via AsyncWebServer
 */

#ifndef LED_API_H
#define LED_API_H

#include <Arduino.h>
#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "SerialLogger.h"
#include "LEDController.h"
#include "NVSManager.h"

// ============================================================================
// LEDApi - HTTP REST API for LED Control
// ============================================================================
// Endpoints:
// - GET  /api/led/status     → Current state
// - POST /api/led/effect     → Change effect
// - POST /api/led/params     → Update parameters  
// - POST /api/led/power      → Power on/off
// - POST /api/led/brightness → Set brightness
// - GET  /api/led/effects    → List all effects
// ============================================================================

class LEDApi {
public:
    // Initialize LED API routes on existing server
    static void begin(AsyncWebServer* server) {
        if (server == nullptr) {
            LOG_ERROR("LEDApi: Server is null!");
            return;
        }
        
        LOG_SECTION("Initializing LED API");
        
        // CORS preflight for LED routes
        server->on("/api/led/*", HTTP_OPTIONS, [](AsyncWebServerRequest *request) {
            AsyncWebServerResponse *response = request->beginResponse(200);
            addCorsHeaders(response);
            request->send(response);
        });
        
        // GET /api/led/status - Get current LED status
        server->on("/api/led/status", HTTP_GET, handleStatus);
        
        // GET /api/led/effects - Get list of all effects
        server->on("/api/led/effects", HTTP_GET, handleEffects);
        
        // GET /api/led/params - Get current effect parameters
        server->on("/api/led/params", HTTP_GET, handleGetParams);
        
        // POST /api/led/effect - Set current effect
        AsyncCallbackJsonWebHandler* effectHandler = new AsyncCallbackJsonWebHandler(
            "/api/led/effect",
            handleSetEffect
        );
        server->addHandler(effectHandler);
        
        // POST /api/led/params - Update effect parameters
        AsyncCallbackJsonWebHandler* paramsHandler = new AsyncCallbackJsonWebHandler(
            "/api/led/params",
            handleSetParams
        );
        server->addHandler(paramsHandler);
        
        // POST /api/led/power - Power on/off
        AsyncCallbackJsonWebHandler* powerHandler = new AsyncCallbackJsonWebHandler(
            "/api/led/power",
            handlePower
        );
        server->addHandler(powerHandler);
        
        // POST /api/led/brightness - Set brightness
        AsyncCallbackJsonWebHandler* brightnessHandler = new AsyncCallbackJsonWebHandler(
            "/api/led/brightness",
            handleBrightness
        );
        server->addHandler(brightnessHandler);
        
        LOG_INFO("LED API endpoints registered");
        LOG_INFO("  GET  /api/led/status");
        LOG_INFO("  GET  /api/led/effects");
        LOG_INFO("  GET  /api/led/params");
        LOG_INFO("  POST /api/led/effect");
        LOG_INFO("  POST /api/led/params");
        LOG_INFO("  POST /api/led/power");
        LOG_INFO("  POST /api/led/brightness");
    }

private:
    // ========================================================================
    // Route Handlers
    // ========================================================================
    
    // GET /api/led/status
    static void handleStatus(AsyncWebServerRequest *request) {
        LOG_DEBUG("GET /api/led/status");
        
        StaticJsonDocument<512> doc;
        LEDController::getStatusJson(doc);
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // GET /api/led/effects
    static void handleEffects(AsyncWebServerRequest *request) {
        LOG_DEBUG("GET /api/led/effects");
        
        StaticJsonDocument<4096> doc;
        LEDController::getEffectsJson(doc);
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // GET /api/led/params
    static void handleGetParams(AsyncWebServerRequest *request) {
        LOG_DEBUG("GET /api/led/params");
        
        StaticJsonDocument<1024> doc;
        LEDController::getParamsJson(doc);
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // POST /api/led/effect
    static void handleSetEffect(AsyncWebServerRequest *request, JsonVariant &json) {
        LOG_DEBUG("POST /api/led/effect");
        
        JsonObject jsonObj = json.as<JsonObject>();
        
        if (!jsonObj.containsKey("id")) {
            sendError(request, 400, "Missing 'id' field");
            return;
        }
        
        uint8_t effectId = jsonObj["id"].as<uint8_t>();
        
        if (effectId >= LEDController::getNumEffects()) {
            sendError(request, 400, "Invalid effect ID");
            return;
        }
        
        LEDController::setEffect(effectId);
        
        // Save to NVS so effect persists after reboot
        NVSManager::saveEffect(effectId);
        
        StaticJsonDocument<256> doc;
        doc["status"] = "ok";
        doc["effect"] = effectId;
        doc["effectName"] = LEDController::getEffectName();
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // POST /api/led/params
    static void handleSetParams(AsyncWebServerRequest *request, JsonVariant &json) {
        LOG_DEBUG("POST /api/led/params");
        
        JsonObject jsonObj = json.as<JsonObject>();
        
        if (jsonObj.size() == 0) {
            sendError(request, 400, "Empty parameters");
            return;
        }
        
        // Apply each parameter
        for (JsonPair kv : jsonObj) {
            LEDController::setParam(kv.key().c_str(), kv.value());
        }
        
        // Save current effect's params to NVS for persistence
        StaticJsonDocument<1024> paramsDoc;
        LEDController::getParamsJson(paramsDoc);
        String paramsJson;
        serializeJson(paramsDoc["params"], paramsJson);
        NVSManager::saveParams(paramsJson);
        
        StaticJsonDocument<128> doc;
        doc["status"] = "ok";
        doc["updated"] = jsonObj.size();
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // POST /api/led/power
    static void handlePower(AsyncWebServerRequest *request, JsonVariant &json) {
        LOG_DEBUG("POST /api/led/power");
        
        JsonObject jsonObj = json.as<JsonObject>();
        
        if (!jsonObj.containsKey("on")) {
            sendError(request, 400, "Missing 'on' field");
            return;
        }
        
        bool powerOn = jsonObj["on"].as<bool>();
        LEDController::setPower(powerOn);
        
        StaticJsonDocument<128> doc;
        doc["status"] = "ok";
        doc["power"] = powerOn;
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // POST /api/led/brightness
    static void handleBrightness(AsyncWebServerRequest *request, JsonVariant &json) {
        LOG_DEBUG("POST /api/led/brightness");
        
        JsonObject jsonObj = json.as<JsonObject>();
        
        if (!jsonObj.containsKey("value")) {
            sendError(request, 400, "Missing 'value' field");
            return;
        }
        
        uint8_t brightness = jsonObj["value"].as<uint8_t>();
        LEDController::setBrightness(brightness);
        
        // Save to NVS only when explicitly requested (when user finishes adjusting)
        bool shouldSave = jsonObj["save"] | false;
        if (shouldSave) {
            NVSManager::saveBrightness(brightness);
        }
        
        StaticJsonDocument<128> doc;
        doc["status"] = "ok";
        doc["brightness"] = brightness;
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(200, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
    
    // ========================================================================
    // Helpers
    // ========================================================================
    
    static void addCorsHeaders(AsyncWebServerResponse *response) {
        response->addHeader("Access-Control-Allow-Origin", HTTP_CORS_ORIGIN);
        response->addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response->addHeader("Access-Control-Allow-Headers", "Content-Type");
    }
    
    static void sendError(AsyncWebServerRequest *request, int code, const char* message) {
        StaticJsonDocument<128> doc;
        doc["error"] = message;
        
        String response;
        serializeJson(doc, response);
        
        AsyncWebServerResponse *res = request->beginResponse(code, "application/json", response);
        addCorsHeaders(res);
        request->send(res);
    }
};

#endif // LED_API_H
