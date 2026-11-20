// Fenexity PLA-746: follow the shared simulation timebase in Redis (ADR 0025 section 3).
//
// A background thread keeps two Redis connections: one subscribed to the change channel,
// one that re-reads the hash after every notification and at least every 5 s. Only the
// business clock (SimClock::BusinessClock) is shared with the main loop. Names are
// resolved with getaddrinfo (Docker DNS), not with mongoose's own resolver.
// Log lines go to stderr, stamped with real time; the URL and password are never logged.

#include "sim_clock_redis.h"
#include "sim_clock_core.h"

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <thread>

#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

namespace SimClock {
namespace {

const int REFRESH_MS = 5000;
const int IO_TIMEOUT_MS = 3000;
const int POLL_SLICE_MS = 250;

std::atomic<bool> g_stop{false};
std::atomic<bool> g_epochChanged{false};
std::thread g_follower;
BusinessClock *g_clock = nullptr;
RedisUrl g_url;
std::string g_readyFile;

std::string jsonEscape(const std::string &value) {
    std::string out;
    for (char c : value) {
        if (c == '"' || c == '\\') {
            out += '\\';
            out += c;
        } else if ((unsigned char) c < 0x20) {
            out += ' ';
        } else {
            out += c;
        }
    }
    return out;
}

std::string field(const char *name, const std::string &value) {
    return std::string(",\"") + name + "\":\"" + jsonEscape(value) + "\"";
}

std::string field(const char *name, long long value) {
    return std::string(",\"") + name + "\":" + std::to_string(value);
}

std::string isoFromMs(int64_t ms) {
    MicroOcpp::Timestamp timestamp;
    char buffer[JSONDATE_LENGTH + 1] = {'\0'};
    if (!toTimestamp(ms, timestamp) || !timestamp.toJsonString(buffer, sizeof(buffer))) return "";
    return buffer;
}

void log(const char *level, const char *event, const std::string &fields = "") {
    // Real time (technical): log timestamps never follow the simulation (ADR 0025 section 1).
    int64_t ms = wallNowMs();
    time_t seconds = (time_t) (ms / 1000);
    struct tm parts;
    gmtime_r(&seconds, &parts);
    char stamp[32];
    snprintf(stamp, sizeof(stamp), "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.tm_year + 1900, parts.tm_mon + 1,
             parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec, (int) (ms % 1000));
    fprintf(stderr, "{\"timestamp\":\"%s\",\"level\":\"%s\",\"event\":\"%s\",\"component\":\"microocpp-sim-clock\"%s}\n",
            stamp, level, event, fields.c_str());
    fflush(stderr);
}

void setReady(bool ready, const Timebase &timebase) {
    if (!ready) {
        unlink(g_readyFile.c_str());
        return;
    }
    FILE *marker = fopen(g_readyFile.c_str(), "w");
    if (!marker) {
        log("error", "clock.sim.ready_marker_failed", field("reason", strerror(errno)));
        return;
    }
    fprintf(marker, "%s %lld\n", timebase.epoch.c_str(), (long long) timebase.revision);
    fclose(marker);
}

class Connection {
public:
    ~Connection() { close(); }

    bool open(const RedisUrl &url, std::string &error) {
        close();
        struct addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        struct addrinfo *addresses = nullptr;
        int status = getaddrinfo(url.host.c_str(), url.port.c_str(), &hints, &addresses);
        if (status != 0) {
            error = std::string("cannot resolve the Redis host: ") + gai_strerror(status);
            return false;
        }
        for (struct addrinfo *address = addresses; address && fd < 0; address = address->ai_next) {
            fd = connectWithTimeout(address, error);
        }
        freeaddrinfo(addresses);
        if (fd < 0) return false;
        RespValue reply;
        if (!url.password.empty()) {
            std::vector<std::string> auth = {"AUTH"};
            if (!url.username.empty()) auth.push_back(url.username);
            auth.push_back(url.password);
            if (!command(auth, reply, error)) {
                error = "Redis authentication failed";
                close();
                return false;
            }
        }
        if (!command({"SELECT", std::to_string(url.db)}, reply, error)) {
            close();
            return false;
        }
        return true;
    }

    bool send(const std::string &data, std::string &error) {
        size_t sent = 0;
        while (sent < data.size()) {
#ifdef MSG_NOSIGNAL
            ssize_t n = ::send(fd, data.data() + sent, data.size() - sent, MSG_NOSIGNAL);
#else
            ssize_t n = ::send(fd, data.data() + sent, data.size() - sent, 0);
#endif
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                struct pollfd p = {fd, POLLOUT, 0};
                if (poll(&p, 1, IO_TIMEOUT_MS) <= 0) {
                    error = "Redis write timed out";
                    return false;
                }
                continue;
            }
            if (n <= 0) {
                error = std::string("Redis write failed: ") + strerror(errno);
                return false;
            }
            sent += (size_t) n;
        }
        return true;
    }

    // 1: a reply was read; 0: nothing within `timeoutMs`; -1: connection or protocol error.
    int read(RespValue &out, int timeoutMs, std::string &error) {
        auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
        while (true) {
            long used = parseReply(buffer, out);
            if (used > 0) {
                buffer.erase(0, (size_t) used);
                return 1;
            }
            if (used < 0) {
                error = "Redis protocol error";
                return -1;
            }
            auto left = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
            if (left <= 0) return 0;
            struct pollfd p = {fd, POLLIN, 0};
            int ready = poll(&p, 1, (int) left);
            if (ready < 0 && errno == EINTR) continue;
            if (ready < 0) {
                error = std::string("Redis poll failed: ") + strerror(errno);
                return -1;
            }
            if (ready == 0) return 0;
            char chunk[4096];
            ssize_t n = recv(fd, chunk, sizeof(chunk), 0);
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) continue;
            if (n <= 0) {
                error = n == 0 ? "Redis closed the connection" : std::string("Redis read failed: ") + strerror(errno);
                return -1;
            }
            buffer.append(chunk, (size_t) n);
        }
    }

    // Sends a command and reads its reply; an error reply counts as a failure.
    bool command(const std::vector<std::string> &args, RespValue &reply, std::string &error) {
        if (!send(encodeCommand(args), error)) return false;
        int status = read(reply, IO_TIMEOUT_MS, error);
        if (status == 0) error = "Redis did not answer " + args[0];
        if (status != 1) return false;
        if (reply.type == RespValue::Error) {
            error = "Redis refused " + args[0];
            return false;
        }
        return true;
    }

    void close() {
        if (fd >= 0) ::close(fd);
        fd = -1;
        buffer.clear();
    }

private:
    int fd = -1;
    std::string buffer;

    static int connectWithTimeout(struct addrinfo *address, std::string &error) {
        int sock = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (sock < 0) {
            error = std::string("socket failed: ") + strerror(errno);
            return -1;
        }
#ifdef SO_NOSIGPIPE
        int one = 1;
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
        fcntl(sock, F_SETFL, fcntl(sock, F_GETFL, 0) | O_NONBLOCK);
        if (connect(sock, address->ai_addr, address->ai_addrlen) < 0 && errno != EINPROGRESS) {
            error = std::string("cannot connect to Redis: ") + strerror(errno);
            ::close(sock);
            return -1;
        }
        struct pollfd p = {sock, POLLOUT, 0};
        int soError = 0;
        socklen_t length = sizeof(soError);
        if (poll(&p, 1, IO_TIMEOUT_MS) <= 0 || getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &length) < 0 || soError != 0) {
            error = "cannot connect to Redis";
            ::close(sock);
            return -1;
        }
        return sock;
    }
};

bool readHash(Connection &connection, std::map<std::string, std::string> &hash, std::string &error) {
    RespValue reply;
    if (!connection.command({"HGETALL", TIMEBASE_KEY}, reply, error)) return false;
    if (!hashFromReply(reply, hash)) {
        error = "unexpected HGETALL reply";
        return false;
    }
    return true;
}

// One re-read applied to the clock; logs transitions only. False when the run ended.
bool applyRead(bool readOk, const std::map<std::string, std::string> &hash, const std::string &readError) {
    bool wasReady = g_clock->ready();
    std::string reason;
    ApplyResult result = readOk ? g_clock->apply(hash, reason) : g_clock->applyError(readError, reason);
    Timebase timebase = g_clock->timebase();
    switch (result) {
        case ApplyResult::EpochChanged:
            log("warn", "clock.sim.epoch_changed", field("clock_epoch", timebase.epoch) + field("reason", reason));
            g_epochChanged.store(true);
            return false;
        case ApplyResult::NotReady:
            if (wasReady) {
                const char *event = !readOk ? "clock.sim.follow_failed"
                        : hash.empty() ? "clock.sim.timebase_missing" : "clock.sim.timebase_invalid";
                log("error", event, field("clock_epoch", timebase.epoch) + field("reason", reason));
            }
            setReady(false, timebase);
            return true;
        case ApplyResult::Adopted:
            log("info", "clock.sim.changed", field("clock_epoch", timebase.epoch) + field("clock_revision", timebase.revision) +
                    field("clock_rate", std::to_string(timebase.rate)) + field("clock_paused", timebase.paused ? "true" : "false"));
            // fall through
        case ApplyResult::Unchanged:
            if (!wasReady) log("info", "clock.sim.recovered", field("clock_epoch", timebase.epoch));
            setReady(true, timebase);
            return true;
    }
    return true;
}

void sleepUnlessStopped(int milliseconds) {
    for (int waited = 0; waited < milliseconds && !g_stop.load(); waited += POLL_SLICE_MS) {
        std::this_thread::sleep_for(std::chrono::milliseconds(POLL_SLICE_MS));
    }
}

void follow() {
    int backoffMs = 1000;
    while (!g_stop.load()) {
        Connection reader;
        Connection subscriber;
        std::string error;
        RespValue reply;
        if (!reader.open(g_url, error) || !subscriber.open(g_url, error) ||
                !subscriber.command({"SUBSCRIBE", CHANGED_CHANNEL}, reply, error)) {
            applyRead(false, {}, error);
            sleepUnlessStopped(backoffMs);
            backoffMs = backoffMs * 2 > REFRESH_MS ? REFRESH_MS : backoffMs * 2;
            continue;
        }
        bool refresh = true;
        auto lastRead = std::chrono::steady_clock::now();
        while (!g_stop.load()) {
            auto sinceRead = std::chrono::steady_clock::now() - lastRead;
            if (refresh || sinceRead >= std::chrono::milliseconds(REFRESH_MS)) {
                std::map<std::string, std::string> hash;
                bool ok = readHash(reader, hash, error);
                if (!applyRead(ok, hash, error)) return;
                if (!ok) {
                    // Like fnx_utils: wait one refresh interval after a failed read.
                    backoffMs = REFRESH_MS;
                    break;
                }
                backoffMs = 1000; // the connection works end to end
                refresh = false;
                lastRead = std::chrono::steady_clock::now();
            }
            RespValue message;
            int status = subscriber.read(message, POLL_SLICE_MS, error);
            if (status < 0) {
                applyRead(false, {}, error);
                break;
            }
            if (status == 1 && message.type == RespValue::Array && !message.items.empty() &&
                    message.items[0].type == RespValue::Bulk && message.items[0].text == "message") {
                refresh = true;
            }
        }
        sleepUnlessStopped(backoffMs);
    }
}

const char *environment(const char *name) {
    return std::getenv(name);
}

std::string trimmed(const char *value) {
    std::string text = value ? value : "";
    size_t begin = text.find_first_not_of(" \t\r\n");
    size_t end = text.find_last_not_of(" \t\r\n");
    return begin == std::string::npos ? "" : text.substr(begin, end - begin + 1);
}

} // namespace

int start() {
    std::string mode = trimmed(std::getenv("FNX_CLOCK"));
    if (mode.empty() || mode == "system") return 0;
    if (mode != "sim") {
        log("error", "clock.sim.refused", field("reason", "FNX_CLOCK must be 'system' or 'sim', got '" + mode + "'"));
        return -1;
    }
    std::string error;
    if (!simulationAllowed(&environment, error)) {
        log("error", "clock.sim.refused", field("reason", error));
        return -1;
    }
    const char *url = std::getenv("FNX_CLOCK_REDIS_URL");
    if (!url || !parseRedisUrl(url, g_url, error)) {
        log("error", "clock.sim.refused", field("reason", url ? error : "FNX_CLOCK_REDIS_URL is required for simulation time"));
        return -1;
    }
    const char *readyFile = std::getenv("FNX_SIM_CLOCK_READY_FILE");
    g_readyFile = readyFile && *readyFile ? readyFile : "/tmp/fnx-sim-clock-ready";
    unlink(g_readyFile.c_str()); // /tmp survives a stop and start of the container

    Connection connection;
    std::map<std::string, std::string> hash;
    Timebase timebase;
    if (!connection.open(g_url, error) || !readHash(connection, hash, error) || parseTimebase(hash, timebase, error) != 1) {
        log("error", "clock.sim.refused", field("reason", error + "; run the new-run procedure first (docs/runbooks/simulation-clock.md)"));
        return -1;
    }
    connection.close();

    g_clock = new BusinessClock(timebase);
    setActiveClock(g_clock);
    setReady(true, timebase);
    log("info", "clock.sim.started", field("clock_epoch", timebase.epoch) + field("clock_revision", timebase.revision) +
            field("business_now", isoFromMs(g_clock->nowMs(wallNowMs()))));
    g_follower = std::thread(follow);
    return 1;
}

bool epochChanged() {
    return g_epochChanged.load();
}

void stop() {
    g_stop.store(true);
    if (g_follower.joinable()) g_follower.join();
}

} // namespace SimClock
