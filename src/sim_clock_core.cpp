// Fenexity PLA-746: shared simulation timebase of ADR 0025; see sim_clock_core.h.

#include "sim_clock_core.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <ctime>

namespace SimClock {

const char *const TIMEBASE_KEY = "fnx:simclock:timebase";
const char *const CHANGED_CHANNEL = "fnx:simclock:changed";
const double MIN_RATE = 1.0;
const double MAX_RATE = 100.0;

namespace {

std::string trim(const std::string &value) {
    size_t begin = 0;
    size_t end = value.size();
    while (begin < end && std::isspace((unsigned char) value[begin])) begin++;
    while (end > begin && std::isspace((unsigned char) value[end - 1])) end--;
    return value.substr(begin, end - begin);
}

std::string lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [] (unsigned char c) { return (char) std::tolower(c); });
    return value;
}

// Python float(): the whole (trimmed) text must be a number.
bool parseDouble(const std::map<std::string, std::string> &hash, const char *field, double &out, std::string &error) {
    auto it = hash.find(field);
    if (it == hash.end()) {
        error = std::string("Invalid simulation timebase: '") + field + "' is missing";
        return false;
    }
    std::string text = trim(it->second);
    char *end = nullptr;
    out = std::strtod(text.c_str(), &end);
    if (text.empty() || end != text.c_str() + text.size()) {
        error = std::string("Invalid simulation timebase: '") + field + "' is " + it->second;
        return false;
    }
    return true;
}

// Python int(): optional sign and digits only.
bool parseInteger(const std::map<std::string, std::string> &hash, const char *field, int64_t &out, std::string &error) {
    auto it = hash.find(field);
    if (it == hash.end()) {
        error = std::string("Invalid simulation timebase: '") + field + "' is missing";
        return false;
    }
    std::string text = trim(it->second);
    size_t start = (!text.empty() && (text[0] == '+' || text[0] == '-')) ? 1 : 0;
    if (text.size() == start || !std::all_of(text.begin() + start, text.end(), [] (unsigned char c) { return std::isdigit(c); })) {
        error = std::string("Invalid simulation timebase: '") + field + "' is " + it->second;
        return false;
    }
    out = std::strtoll(text.c_str(), nullptr, 10);
    return true;
}

int hexValue(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool percentDecode(const std::string &in, std::string &out) {
    out.clear();
    for (size_t i = 0; i < in.size(); i++) {
        if (in[i] != '%') {
            out += in[i];
            continue;
        }
        if (i + 2 >= in.size() || hexValue(in[i + 1]) < 0 || hexValue(in[i + 2]) < 0) return false;
        out += (char) (hexValue(in[i + 1]) * 16 + hexValue(in[i + 2]));
        i += 2;
    }
    return true;
}

long parseAt(const std::string &buffer, size_t pos, RespValue &out) {
    size_t lineEnd = buffer.find("\r\n", pos);
    if (lineEnd == std::string::npos) return 0;
    if (lineEnd == pos) return -1;
    char type = buffer[pos];
    std::string line = buffer.substr(pos + 1, lineEnd - pos - 1);
    size_t next = lineEnd + 2;
    char *end = nullptr;
    switch (type) {
        case '+':
            out = RespValue();
            out.type = RespValue::SimpleString;
            out.text = line;
            return (long) (next - pos);
        case '-':
            out = RespValue();
            out.type = RespValue::Error;
            out.text = line;
            return (long) (next - pos);
        case ':':
            out = RespValue();
            out.type = RespValue::Integer;
            out.integer = std::strtoll(line.c_str(), &end, 10);
            if (line.empty() || end != line.c_str() + line.size()) return -1;
            return (long) (next - pos);
        case '$': {
            long length = std::strtol(line.c_str(), &end, 10);
            if (line.empty() || end != line.c_str() + line.size()) return -1;
            out = RespValue();
            if (length < 0) {
                out.type = RespValue::Nil;
                return (long) (next - pos);
            }
            if (buffer.size() < next + (size_t) length + 2) return 0;
            if (buffer.compare(next + (size_t) length, 2, "\r\n") != 0) return -1;
            out.type = RespValue::Bulk;
            out.text = buffer.substr(next, (size_t) length);
            return (long) (next + (size_t) length + 2 - pos);
        }
        case '*': {
            long count = std::strtol(line.c_str(), &end, 10);
            if (line.empty() || end != line.c_str() + line.size()) return -1;
            out = RespValue();
            if (count < 0) {
                out.type = RespValue::Nil;
                return (long) (next - pos);
            }
            out.type = RespValue::Array;
            size_t cursor = next;
            for (long i = 0; i < count; i++) {
                RespValue item;
                long used = parseAt(buffer, cursor, item);
                if (used <= 0) return used;
                out.items.push_back(item);
                cursor += (size_t) used;
            }
            return (long) (cursor - pos);
        }
        default:
            return -1;
    }
}

} // namespace

int parseTimebase(const std::map<std::string, std::string> &hash, Timebase &out, std::string &error) {
    if (hash.empty()) {
        error = "no simulation timebase";
        return 0;
    }
    auto paused = hash.find("paused");
    std::string pausedText = paused == hash.end() ? "" : paused->second;
    if (pausedText != "0" && pausedText != "1") {
        error = "Simulation timebase field 'paused' must be 0 or 1, got '" + pausedText + "'";
        return -1;
    }
    Timebase timebase;
    timebase.paused = pausedText == "1";
    auto epoch = hash.find("epoch");
    timebase.epoch = epoch == hash.end() ? "" : epoch->second;
    if (!parseDouble(hash, "wall_anchor", timebase.wallAnchor, error) ||
            !parseDouble(hash, "sim_anchor", timebase.simAnchor, error) ||
            !parseDouble(hash, "rate", timebase.rate, error) ||
            !parseInteger(hash, "revision", timebase.revision, error)) {
        return -1;
    }
    if (!std::isfinite(timebase.wallAnchor) || !std::isfinite(timebase.simAnchor)) {
        error = "Simulation timebase has a non-finite anchor";
        return -1;
    }
    if (timebase.epoch.empty()) {
        error = "Simulation timebase has no epoch";
        return -1;
    }
    if (!(timebase.rate >= MIN_RATE && timebase.rate <= MAX_RATE)) {
        error = "Simulation rate is outside [1, 100]";
        return -1;
    }
    if (timebase.revision < 1) {
        error = "Simulation revision is below 1";
        return -1;
    }
    out = timebase;
    return 1;
}

double simSeconds(const Timebase &timebase, double wallSeconds) {
    if (timebase.paused) return timebase.simAnchor;
    return timebase.simAnchor + (wallSeconds - timebase.wallAnchor) * timebase.rate;
}

bool simulationAllowed(const char *(*getenv)(const char *), std::string &error) {
    const char *deploymentClass = getenv("FENEXITY_DEPLOYMENT_CLASS");
    if (!deploymentClass || std::string(deploymentClass) != "development") {
        error = std::string("Simulation time requires FENEXITY_DEPLOYMENT_CLASS=development; found '") +
                (deploymentClass ? deploymentClass : "") + "'";
        return false;
    }
    const char *environment = getenv("ENVIRONMENT");
    if (environment && lower(trim(environment)) == "production") {
        error = "Simulation time is refused because ENVIRONMENT=production is set";
        return false;
    }
    const char *fenexityEnvironment = getenv("FENEXITY_ENVIRONMENT");
    std::string fenexity = fenexityEnvironment ? lower(trim(fenexityEnvironment)) : "";
    if (fenexity == "prod" || fenexity == "production") {
        error = "Simulation time is refused because FENEXITY_ENVIRONMENT=" + fenexity;
        return false;
    }
    return true;
}

bool parseRedisUrl(const std::string &url, RedisUrl &out, std::string &error) {
    const std::string scheme = "redis://";
    if (url.compare(0, scheme.size(), scheme) != 0) {
        error = "FNX_CLOCK_REDIS_URL must start with redis://";
        return false;
    }
    std::string rest = url.substr(scheme.size());
    RedisUrl parsed;
    size_t at = rest.rfind('@');
    if (at != std::string::npos) {
        std::string userinfo = rest.substr(0, at);
        rest = rest.substr(at + 1);
        size_t colon = userinfo.find(':');
        std::string user = colon == std::string::npos ? "" : userinfo.substr(0, colon);
        std::string password = colon == std::string::npos ? userinfo : userinfo.substr(colon + 1);
        if (!percentDecode(user, parsed.username) || !percentDecode(password, parsed.password)) {
            error = "FNX_CLOCK_REDIS_URL has an invalid percent-encoding";
            return false;
        }
    }
    size_t slash = rest.find('/');
    std::string hostport = rest.substr(0, slash);
    if (slash != std::string::npos && slash + 1 < rest.size()) {
        std::string db = rest.substr(slash + 1);
        if (!std::all_of(db.begin(), db.end(), [] (unsigned char c) { return std::isdigit(c); })) {
            error = "FNX_CLOCK_REDIS_URL has an invalid database";
            return false;
        }
        parsed.db = std::atoi(db.c_str());
    }
    size_t colon = hostport.rfind(':');
    parsed.host = colon == std::string::npos ? hostport : hostport.substr(0, colon);
    if (colon != std::string::npos) parsed.port = hostport.substr(colon + 1);
    if (parsed.host.empty() || parsed.port.empty()) {
        error = "FNX_CLOCK_REDIS_URL has no host";
        return false;
    }
    out = parsed;
    return true;
}

std::string encodeCommand(const std::vector<std::string> &args) {
    std::string out = "*" + std::to_string(args.size()) + "\r\n";
    for (const auto &arg : args) {
        out += "$" + std::to_string(arg.size()) + "\r\n" + arg + "\r\n";
    }
    return out;
}

long parseReply(const std::string &buffer, RespValue &out) {
    if (buffer.empty()) return 0;
    return parseAt(buffer, 0, out);
}

bool hashFromReply(const RespValue &reply, std::map<std::string, std::string> &out) {
    if (reply.type != RespValue::Array || reply.items.size() % 2 != 0) return false;
    out.clear();
    for (size_t i = 0; i < reply.items.size(); i += 2) {
        if (reply.items[i].type != RespValue::Bulk || reply.items[i + 1].type != RespValue::Bulk) return false;
        out[reply.items[i].text] = reply.items[i + 1].text;
    }
    return true;
}

BusinessClock::BusinessClock(const Timebase &initial) : current(initial) {}

int64_t BusinessClock::nowMs(int64_t wallMs) {
    std::lock_guard<std::mutex> lock(mutex);
    auto computed = (int64_t) std::floor(simSeconds(current, wallMs / 1000.0) * 1000.0);
    floorMs = std::max(floorMs, computed);
    return floorMs;
}

ApplyResult BusinessClock::apply(const std::map<std::string, std::string> &hash, std::string &reason) {
    Timebase next;
    int parsed = parseTimebase(hash, next, reason);
    std::lock_guard<std::mutex> lock(mutex);
    if (parsed != 1) {
        isReady = false;
        return ApplyResult::NotReady;
    }
    if (next.epoch != current.epoch) {
        reason = "epoch " + next.epoch + " replaces " + current.epoch;
        return ApplyResult::EpochChanged;
    }
    isReady = true;
    if (next.revision <= current.revision) return ApplyResult::Unchanged;
    current = next;
    return ApplyResult::Adopted;
}

ApplyResult BusinessClock::applyError(const std::string &error, std::string &reason) {
    std::lock_guard<std::mutex> lock(mutex);
    reason = error;
    isReady = false;
    return ApplyResult::NotReady;
}

Timebase BusinessClock::timebase() {
    std::lock_guard<std::mutex> lock(mutex);
    return current;
}

bool BusinessClock::ready() {
    std::lock_guard<std::mutex> lock(mutex);
    return isReady;
}

int64_t wallNowMs() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

bool toTimestamp(int64_t businessMs, MicroOcpp::Timestamp &out) {
    int64_t seconds = businessMs >= 0 ? businessMs / 1000 : (businessMs - 999) / 1000;
    time_t raw = (time_t) seconds;
    struct tm parts;
    if (!gmtime_r(&raw, &parts)) return false;
#if MO_ENABLE_TIMESTAMP_MILLISECONDS
    MicroOcpp::Timestamp timestamp(
            (int16_t) (parts.tm_year + 1900), (int16_t) parts.tm_mon, (int16_t) (parts.tm_mday - 1),
            parts.tm_hour, parts.tm_min, parts.tm_sec, (int32_t) (businessMs - seconds * 1000));
#else
    MicroOcpp::Timestamp timestamp(
            (int16_t) (parts.tm_year + 1900), (int16_t) parts.tm_mon, (int16_t) (parts.tm_mday - 1),
            parts.tm_hour, parts.tm_min, parts.tm_sec);
#endif
    if (timestamp < MicroOcpp::MIN_TIME || timestamp >= MicroOcpp::MAX_TIME) return false;
    out = timestamp;
    return true;
}

double energyWh(double powerW, int64_t elapsedMs) {
    if (elapsedMs <= 0) return 0;
    return powerW * (double) elapsedMs / 3600000.0;
}

namespace {
std::atomic<BusinessClock *> activeClock{nullptr};
}

void setActiveClock(BusinessClock *clock) {
    activeClock.store(clock);
}

bool active() {
    return activeClock.load() != nullptr;
}

int64_t activeNowMs() {
    BusinessClock *clock = activeClock.load();
    return clock ? clock->nowMs(wallNowMs()) : 0;
}

bool activeTimestamp(MicroOcpp::Timestamp &out) {
    BusinessClock *clock = activeClock.load();
    return clock && toTimestamp(clock->nowMs(wallNowMs()), out);
}

} // namespace SimClock
