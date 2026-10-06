#include "typing.h"

static const typing_key_t all_up = {0, 0};

static bool deliver(const typing_port_t *port, typing_key_t key, unsigned max_waits) {
  for (unsigned waited = 0; !port->ready(port->ctx); waited++) {
    if (waited == max_waits) return false;
    port->sleep(port->ctx);
  }
  return port->send(port->ctx, key);
}

bool typing_run(const typing_port_t *port, const typing_key_t *keys, size_t count, unsigned max_waits) {
  for (size_t i = 0; i < count; i++) {
    if (!deliver(port, keys[i], max_waits) || !deliver(port, all_up, max_waits)) {
      deliver(port, all_up, max_waits);
      return false;
    }
  }
  return true;
}
