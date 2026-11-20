// Fenexity PLA-746: follow the shared simulation timebase in Redis (ADR 0025 section 3).
//
// Active only with FNX_CLOCK=sim. Without it (normal development, demo and production
// runs) the simulator keeps its tick-based clock and nothing here runs.

#ifndef MO_SIM_CLOCK_REDIS_H
#define MO_SIM_CLOCK_REDIS_H

namespace SimClock {

// Exit status of the simulator when the run (epoch) changes; Compose restarts it.
const int EPOCH_CHANGED_EXIT = 75;

// Reads FNX_CLOCK. Returns 0 when simulation time is off, 1 when it was started
// (guard passed, initial timebase read, follower running), -1 when the simulator
// must not start (the reason is logged).
int start();

// True once a different epoch was seen; the main loop then ends the process.
bool epochChanged();

// Stops the follower thread.
void stop();

} // namespace SimClock

#endif
