// Fenexity PLA-746: unit tests of the simulation clock (ADR 0025 timebase contract).

#include "catch.hpp"

#include <map>
#include <string>

#include <MicroOcpp/Core/Time.h>

#include "sim_clock_core.h"

using namespace SimClock;

namespace {

std::map<std::string, std::string> validHash() {
    return {{"epoch", "e1"}, {"revision", "3"}, {"wall_anchor", "1000"}, {"sim_anchor", "5000"},
            {"rate", "60"}, {"paused", "0"}, {"pause_reason", ""}};
}

std::map<std::string, std::string> fakeEnv;

const char *fakeGetenv(const char *name) {
    auto it = fakeEnv.find(name);
    return it == fakeEnv.end() ? nullptr : it->second.c_str();
}

std::string iso(const MicroOcpp::Timestamp &timestamp) {
    char buffer[JSONDATE_LENGTH + 1] = {'\0'};
    timestamp.toJsonString(buffer, sizeof(buffer));
    return buffer;
}

MicroOcpp::Timestamp g_sourceTime;
bool g_sourceAnswers = true;

bool fakeSource(MicroOcpp::Timestamp &out) {
    if (!g_sourceAnswers) return false;
    out = g_sourceTime;
    return true;
}

} // namespace

TEST_CASE("A valid timebase hash is parsed like fnx_utils") {
    Timebase timebase;
    std::string error;
    REQUIRE(parseTimebase(validHash(), timebase, error) == 1);
    CHECK(timebase.epoch == "e1");
    CHECK(timebase.revision == 3);
    CHECK(timebase.wallAnchor == 1000);
    CHECK(timebase.simAnchor == 5000);
    CHECK(timebase.rate == 60);
    CHECK_FALSE(timebase.paused);
    CHECK(parseTimebase({}, timebase, error) == 0);
}

TEST_CASE("Invalid timebase fields are rejected") {
    const std::map<std::string, std::string> changes[] = {
        {{"paused", "true"}}, {{"sim_anchor", "soon"}}, {{"sim_anchor", "inf"}}, {{"epoch", ""}},
        {{"rate", "0.5"}}, {{"rate", "101"}}, {{"revision", "2.0"}}, {{"revision", "0"}},
    };
    for (const auto &change : changes) {
        auto hash = validHash();
        for (const auto &entry : change) hash[entry.first] = entry.second;
        Timebase timebase;
        std::string error;
        CHECK(parseTimebase(hash, timebase, error) == -1);
    }
    auto missing = validHash();
    missing.erase("wall_anchor");
    Timebase timebase;
    std::string error;
    CHECK(parseTimebase(missing, timebase, error) == -1);
}

TEST_CASE("Business time follows the anchor formula and stands still while paused") {
    Timebase timebase;
    std::string error;
    REQUIRE(parseTimebase(validHash(), timebase, error) == 1);
    CHECK(simSeconds(timebase, 1010) == 5000 + 10 * 60);
    timebase.paused = true;
    CHECK(simSeconds(timebase, 1010) == 5000);
}

TEST_CASE("The business clock follows revisions and never goes backwards") {
    Timebase timebase;
    std::string error;
    REQUIRE(parseTimebase(validHash(), timebase, error) == 1);
    BusinessClock clock(timebase);
    CHECK(clock.nowMs(1000000) == 5000000);
    CHECK(clock.nowMs(1001000) == 5060000); // rate 60

    auto slower = validHash();
    slower["revision"] = "4";
    slower["rate"] = "1";
    slower["sim_anchor"] = "4000"; // earlier than the time already reported
    std::string reason;
    CHECK(clock.apply(slower, reason) == ApplyResult::Adopted);
    CHECK(clock.nowMs(1001000) == 5060000); // floor

    auto older = validHash();
    older["revision"] = "2";
    CHECK(clock.apply(older, reason) == ApplyResult::Unchanged);
    CHECK(clock.timebase().revision == 4);
}

TEST_CASE("Missing or invalid hashes and read errors keep the time and report not ready") {
    Timebase timebase;
    std::string error;
    REQUIRE(parseTimebase(validHash(), timebase, error) == 1);
    BusinessClock clock(timebase);
    std::string reason;
    CHECK(clock.apply({}, reason) == ApplyResult::NotReady);
    CHECK_FALSE(clock.ready());
    CHECK(clock.nowMs(1001000) == 5060000);
    CHECK(clock.apply(validHash(), reason) == ApplyResult::Unchanged);
    CHECK(clock.ready());
    auto invalid = validHash();
    invalid["rate"] = "500";
    CHECK(clock.apply(invalid, reason) == ApplyResult::NotReady);
    CHECK(clock.applyError("connection lost", reason) == ApplyResult::NotReady);
    CHECK_FALSE(clock.ready());
}

TEST_CASE("A new epoch ends the run") {
    Timebase timebase;
    std::string error;
    REQUIRE(parseTimebase(validHash(), timebase, error) == 1);
    BusinessClock clock(timebase);
    auto next = validHash();
    next["epoch"] = "e2";
    std::string reason;
    CHECK(clock.apply(next, reason) == ApplyResult::EpochChanged);
}

TEST_CASE("Simulation time is refused outside development") {
    std::string error;
    fakeEnv = {{"FENEXITY_DEPLOYMENT_CLASS", "development"}};
    CHECK(simulationAllowed(&fakeGetenv, error));
    const std::map<std::string, std::string> refused[] = {
        {},
        {{"FENEXITY_DEPLOYMENT_CLASS", "demo"}},
        {{"FENEXITY_DEPLOYMENT_CLASS", "development"}, {"ENVIRONMENT", " Production "}},
        {{"FENEXITY_DEPLOYMENT_CLASS", "development"}, {"FENEXITY_ENVIRONMENT", "prod"}},
    };
    for (const auto &env : refused) {
        fakeEnv = env;
        CHECK_FALSE(simulationAllowed(&fakeGetenv, error));
    }
}

TEST_CASE("The Redis URL is parsed with a percent-encoded password") {
    RedisUrl url;
    std::string error;
    REQUIRE(parseRedisUrl("redis://:p%40ss%3Aw0rd@fenexity-redis:6379/15", url, error));
    CHECK(url.host == "fenexity-redis");
    CHECK(url.port == "6379");
    CHECK(url.password == "p@ss:w0rd");
    CHECK(url.username.empty());
    CHECK(url.db == 15);
    REQUIRE(parseRedisUrl("redis://redis-host", url, error));
    CHECK(url.port == "6379");
    CHECK(url.db == 0);
    CHECK_FALSE(parseRedisUrl("http://redis:6379/15", url, error));
    CHECK_FALSE(parseRedisUrl("redis://:bad%zz@redis/15", url, error));
}

TEST_CASE("RESP2 commands are encoded and replies parsed incrementally") {
    CHECK(encodeCommand({"HGETALL", "k"}) == "*2\r\n$7\r\nHGETALL\r\n$1\r\nk\r\n");

    std::string reply = "*4\r\n$5\r\nepoch\r\n$2\r\ne1\r\n$4\r\nrate\r\n$2\r\n60\r\n";
    RespValue value;
    for (size_t cut = 0; cut < reply.size(); cut++) {
        CHECK(parseReply(reply.substr(0, cut), value) == 0);
    }
    REQUIRE(parseReply(reply + "+OK\r\n", value) == (long) reply.size());
    std::map<std::string, std::string> hash;
    REQUIRE(hashFromReply(value, hash));
    CHECK(hash["epoch"] == "e1");
    CHECK(hash["rate"] == "60");

    REQUIRE(parseReply("-NOAUTH Authentication required.\r\n", value) > 0);
    CHECK(value.type == RespValue::Error);
    REQUIRE(parseReply("$-1\r\n", value) > 0);
    CHECK(value.type == RespValue::Nil);
    REQUIRE(parseReply("*0\r\n", value) > 0);
    REQUIRE(hashFromReply(value, hash));
    CHECK(hash.empty());
    CHECK(parseReply("?bogus\r\n", value) == -1);
}

TEST_CASE("Business milliseconds become OCPP timestamps") {
    MicroOcpp::Timestamp timestamp;
    REQUIRE(toTimestamp(1803873630586LL, timestamp)); // 2027-03-01T04:00:30.586Z
    CHECK(iso(timestamp) == "2027-03-01T04:00:30.586Z");
    REQUIRE(toTimestamp(1830211200000LL, timestamp)); // 2027-12-31T00:00:00Z
    CHECK(iso(timestamp) == "2027-12-31T00:00:00.000Z");
    CHECK_FALSE(toTimestamp(0, timestamp)); // before MIN_TIME
}

TEST_CASE("Energy accrues over elapsed business time") {
    CHECK(energyWh(11000, 3600000) == Approx(11000)); // one simulated hour at 11 kW
    CHECK(energyWh(11000, 0) == 0);
    CHECK(energyWh(11000, -5) == 0);
}

TEST_CASE("The clock hook answers only after the CSMS set the time") {
    MicroOcpp::Clock clock;
    g_sourceAnswers = true;
    REQUIRE(g_sourceTime.setTime("2027-03-01T04:00:30.586Z"));
    clock.setTimeSource(&fakeSource);
    CHECK(clock.now() < MicroOcpp::MIN_TIME); // not set by the CSMS yet: unchanged pre-boot time

    REQUIRE(clock.setTime("2026-11-20T12:00:00.000Z"));
    CHECK(iso(clock.now()) == "2027-03-01T04:00:30.586Z");

    g_sourceAnswers = false; // without an answer it keeps running from the last value
    CHECK(clock.now() >= g_sourceTime);

    clock.setTimeSource(nullptr);
    REQUIRE(clock.setTime("2026-11-20T12:00:00.000Z"));
    CHECK(iso(clock.now()).compare(0, 19, "2026-11-20T12:00:00") == 0);
}
