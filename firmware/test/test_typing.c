// Host tests for typing.c: the press and release sequence behind touch
// unlock, against a fake keyboard endpoint whose host takes each report a
// few scheduler ticks after it is sent (ADR-0022).
#include <stdio.h>
#include <string.h>

#include "typing.h"

static int failures = 0;
#define CHECK(cond, name) do { if (cond) printf("ok   %s\n", name); else { printf("FAIL %s\n", name); failures++; } } while (0)

typedef struct {
  unsigned latency;     // sleeps before the host takes a report
  unsigned until_ready;
  int fail_send;        // index of the send that fails, -1 for none
  bool host_gone_after; // after the first report the host never polls again
  typing_key_t sent[32];
  size_t sent_count;
  unsigned sleeps;
} fake_t;

static bool fake_ready(void *ctx) {
  fake_t *f = ctx;
  return f->until_ready == 0;
}

static bool fake_send(void *ctx, typing_key_t key) {
  fake_t *f = ctx;
  if ((int)f->sent_count == f->fail_send) { f->fail_send = -1; return false; }
  f->sent[f->sent_count++] = key;
  f->until_ready = f->host_gone_after ? 1000000 : f->latency;
  return true;
}

static void fake_sleep(void *ctx) {
  fake_t *f = ctx;
  f->sleeps++;
  if (f->until_ready && f->until_ready < 1000000) f->until_ready--;
}

#define K(code) ((typing_key_t){0, (code)})
#define UP ((typing_key_t){0, 0})

static bool same(typing_key_t a, typing_key_t b) { return a.modifier == b.modifier && a.code == b.code; }

static bool sent_is(const fake_t *f, const typing_key_t *want, size_t n) {
  if (f->sent_count != n) return false;
  for (size_t i = 0; i < n; i++) if (!same(f->sent[i], want[i])) return false;
  return true;
}

static typing_port_t port_for(fake_t *f) {
  return (typing_port_t){.ready = fake_ready, .send = fake_send, .sleep = fake_sleep, .ctx = f};
}

static void test_pairs(void) {
  fake_t f = {.latency = 1, .fail_send = -1};
  typing_port_t port = port_for(&f);
  const typing_key_t keys[] = {{0x02, 0x04}, K(0x62), K(0x28)};
  const typing_key_t expect[] = {{0x02, 0x04}, UP, K(0x62), UP, K(0x28), UP};
  CHECK(typing_run(&port, keys, 3, 50), "types every key");
  CHECK(sent_is(&f, expect, 6), "each key down with its modifier, then all up");
}

static void test_slow_host(void) {
  // The host polls every 10 ms and the tick is 10 ms, so a report can wait a
  // few ticks to be taken; that is not a failure.
  fake_t f = {.latency = 3, .fail_send = -1};
  typing_port_t port = port_for(&f);
  const typing_key_t keys[] = {K(0x59), K(0x5A), K(0x5B), K(0x5C), K(0x5D), K(0x5E), K(0x28)};
  CHECK(typing_run(&port, keys, 7, 50), "waits for a slow host instead of giving up");
  CHECK(f.sent_count == 14 && same(f.sent[13], UP), "and ends with every key up");
}

static void test_failed_release_is_retried(void) {
  fake_t f = {.latency = 1, .fail_send = 1};  // the release after the first key
  typing_port_t port = port_for(&f);
  const typing_key_t keys[] = {K(0x62), K(0x59), K(0x28)};
  const typing_key_t expect[] = {K(0x62), UP};
  CHECK(!typing_run(&port, keys, 3, 50), "reports the failure");
  CHECK(sent_is(&f, expect, 2), "still releases the key it pressed, and stops");
}

static void test_failed_press_still_releases(void) {
  fake_t f = {.latency = 1, .fail_send = 2};  // the second key's press
  typing_port_t port = port_for(&f);
  const typing_key_t keys[] = {K(0x62), K(0x59), K(0x28)};
  CHECK(!typing_run(&port, keys, 3, 50), "a failed press fails the run");
  CHECK(f.sent_count == 3 && same(f.sent[2], UP), "and the last report is all keys up");
}

static void test_host_gone_is_bounded(void) {
  fake_t f = {.latency = 1, .fail_send = -1, .host_gone_after = true};
  typing_port_t port = port_for(&f);
  const typing_key_t keys[] = {K(0x62), K(0x59), K(0x28)};
  CHECK(!typing_run(&port, keys, 3, 50), "a host that stops polling fails the run");
  CHECK(f.sleeps <= 2 * 50, "after a bounded wait");
}

int main(void) {
  test_pairs();
  test_slow_host();
  test_failed_release_is_retried();
  test_failed_press_still_releases();
  test_host_gone_is_bounded();
  if (failures) {
    printf("%d failed\n", failures);
    return 1;
  }
  printf("all passed\n");
  return 0;
}
