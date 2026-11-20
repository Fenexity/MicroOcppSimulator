// Fenexity PLA-746: shared simulation timebase of ADR 0025 for the simulator.
//
// Pure parts without I/O: the timebase contract (same fields, validation and formula
// as fnx_utils.clock and the CitrineOS preload of the Hub), the business clock with
// its monotonic floor, the participant rules for a re-read hash, the development-only
// guard, the Redis URL and RESP2 helpers, and the energy formula. Built into every
// target; the Redis follower (sim_clock_redis) exists only for the mongoose build.

#ifndef MO_SIM_CLOCK_CORE_H
#define MO_SIM_CLOCK_CORE_H

#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include <MicroOcpp/Core/Time.h>

namespace SimClock {

extern const char *const TIMEBASE_KEY;    // "fnx:simclock:timebase"
extern const char *const CHANGED_CHANNEL; // "fnx:simclock:changed"
extern const double MIN_RATE;
extern const double MAX_RATE;

struct Timebase {
    std::string epoch;
    int64_t revision = 0;
    double wallAnchor = 0; // real Unix seconds
    double simAnchor = 0;  // business Unix seconds
    double rate = 1;
    bool paused = false;
};

// Parse the Redis hash like fnx_utils.clock.Timebase.from_hash.
// Returns 1 for a valid timebase, 0 for an empty hash (no timebase), -1 when invalid.
int parseTimebase(const std::map<std::string, std::string> &hash, Timebase &out, std::string &error);

// Business Unix seconds at the real Unix time `wallSeconds`.
double simSeconds(const Timebase &timebase, double wallSeconds);

// Refuse simulation time outside development stacks (ADR 0025 section 6, fail closed).
// `getenv` is injectable for tests. Returns false and sets `error` when refused.
bool simulationAllowed(const char *(*getenv)(const char *), std::string &error);

// redis://[user]:password@host:port/db with a percent-encoded password.
struct RedisUrl {
    std::string host;
    std::string port = "6379";
    std::string username;
    std::string password;
    int db = 0;
};
bool parseRedisUrl(const std::string &url, RedisUrl &out, std::string &error);

// RESP2 command encoding and an incremental reply parser.
std::string encodeCommand(const std::vector<std::string> &args);

struct RespValue {
    enum Type { SimpleString, Error, Integer, Bulk, Nil, Array } type = Nil;
    std::string text;               // SimpleString, Error, Bulk
    long long integer = 0;          // Integer
    std::vector<RespValue> items;   // Array
};
// Parses one reply from the start of `buffer`. Returns the consumed byte count, 0 when
// the reply is incomplete, -1 on a protocol error.
long parseReply(const std::string &buffer, RespValue &out);

// Flat HGETALL reply to a map; false if the reply is not an array of bulk strings.
bool hashFromReply(const RespValue &reply, std::map<std::string, std::string> &out);

// What one re-read of the hash means for the running process (ADR 0025 section 3).
enum class ApplyResult {
    Adopted,      // same epoch, higher revision: business time follows it now
    Unchanged,    // same epoch, same or lower revision
    NotReady,     // missing or invalid hash, or a read error: last timebase kept
    EpochChanged, // another run: the process must end (exit 75) and restart
};

// Business clock of one epoch; thread safe (the follower applies, the main loop reads).
class BusinessClock {
public:
    explicit BusinessClock(const Timebase &initial);

    // Business Unix milliseconds at `wallMs`, never decreasing within the process.
    int64_t nowMs(int64_t wallMs);

    ApplyResult apply(const std::map<std::string, std::string> &hash, std::string &reason);
    ApplyResult applyError(const std::string &error, std::string &reason);

    Timebase timebase();
    bool ready();

private:
    std::mutex mutex;
    Timebase current;
    int64_t floorMs = INT64_MIN;
    bool isReady = true;
};

// Real Unix milliseconds (technical time).
int64_t wallNowMs();

// Business milliseconds to a MicroOcpp Timestamp; false outside [MIN_TIME, MAX_TIME).
bool toTimestamp(int64_t businessMs, MicroOcpp::Timestamp &out);

// Energy in Wh delivered at `powerW` over `elapsedMs` of business time.
double energyWh(double powerW, int64_t elapsedMs);

// The process-wide clock while simulation time is active (set by the follower).
void setActiveClock(BusinessClock *clock);
bool active();
int64_t activeNowMs();
// MicroOcpp::Clock time source: business time of the active clock.
bool activeTimestamp(MicroOcpp::Timestamp &out);

} // namespace SimClock

#endif
