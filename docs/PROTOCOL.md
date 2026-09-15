# Wire protocols

Two links, one style: UTF-8 text, one message per line, `\n` terminated
(`\r` ignored), at most 256 bytes. Verbs are upper-case on the device link and
lower-case on the control socket. Fields after the verb are `key=value` tokens
separated by single spaces. Values never contain spaces except the final
`reason=` field, which may run to the end of the line.

## Device link (USB CDC, protocol 1)

### Commands and responses

Every command gets exactly one response line, `OK <VERB> ...` or
`ERR <VERB> reason=<token>`. Commands run in order. `IDENTIFY`, `ENROLL` and
`PAIR` are long-running; only one may be in flight, others get `reason=busy`.
`CANCEL` is handled out of band and makes the in-flight command finish with
`reason=cancelled`.

| command | response | notes |
| -- | -- | -- |
| `PING` | `OK PONG proto=1 fw=0.1.0` | |
| `STATUS` | `OK STATUS fw=0.1.0 proto=1 sensor=ready\|offline prints=N touch=pin\|poll finger=0\|1 watch=on\|off idle=<colour> ring=<mode>:<colour>` | |
| `LED <mode> [<colour>] [<colour2>] [<cycles>]` | `OK LED` | temporary ring state until the next `LED` or `IDLE`. `cycles` 0 means forever. |
| `IDLE <colour>` | `OK IDLE` | the state the ring returns to. Persisted in NVS. |
| `IDENTIFY timeout=<ms> [prompt=<colour>] [nonce=<hex32>]` | `OK IDENTIFY slot=N score=S [mac=<hex64>]` or `ERR IDENTIFY reason=timeout\|cancelled\|sensor\|busy` | ring breathes `prompt` (default blue) while waiting. Each failed attempt emits `EVT NOMATCH` and flashes red, then keeps waiting. `mac` = HMAC-SHA256(device_key, "IDENTIFY\|nonce\|slot") when a nonce was given. |
| `ENROLL slot=<n>` | `OK ENROLL slot=N` or `ERR ENROLL reason=slot\|timeout\|cancelled\|sensor\|busy\|failed` | emits `EVT ENROLL step=...` as it goes. Two captures. |
| `DELETE slot=<n>` / `DELETE all` | `OK DELETE` | |
| `SLOTS` | `OK SLOTS used=1,3 capacity=20` | from the sensor index table. |
| `WATCH on\|off` | `OK WATCH` | on: every touch runs an identify and emits `EVT MATCH` or `EVT NOMATCH`. Default off. |
| `TOUCH pin\|poll` | `OK TOUCH` | presence source. `poll` asks the sensor for an image every 150 ms and works with no TouchOut wire. Persisted. |
| `PAIR` | `OK PAIR key=<hex64>` or `ERR PAIR reason=...` | returns the device key once per boot, after a fingerprint match. Used by the PAM install. |
| `REBOOT` | `OK REBOOT` | |
| `BOOTLOADER` | `ERR BOOTLOADER reason=unsupported` | reserved. Meant to reboot into ROM download mode; neither known sequence works on this board yet, and a failed attempt kills the USB link until a power cycle, so it is compiled out. |
| `GPIO` | `OK GPIO 3=0 4=1 5=0 ...` | levels of the unused XIAO pins, for confirming where a wire landed. |
| `CANCEL` | `OK CANCEL` | |
| anything else | `ERR COMMAND reason=unknown` | |

Colours: `off blue green cyan red magenta yellow white`. These are the seven
combinations the ring's three channels can make, plus off.

Modes: `off on breathe flash fadein fadeout`.

### Events

Unsolicited, may arrive at any time including between a command and its
response.

| event | when |
| -- | -- |
| `EVT READY fw=0.1.0 proto=1` | boot, and whenever the host opens the port |
| `EVT SENSOR state=ready\|offline` | sensor health changes |
| `EVT TOUCH state=down\|up` | presence edge |
| `EVT TAP count=N` | 300 ms after the last lift of a short-touch sequence |
| `EVT HOLD` | touch held 800 ms, once per touch |
| `EVT MATCH slot=N score=S` | watch mode, or an identify attempt succeeded |
| `EVT NOMATCH` | a finger was read but matched no template |
| `EVT ENROLL step=touch\|lift\|touch_again\|processing` | enrolment progress |

### Example session

```
> PING
< OK PONG proto=1 fw=0.1.0
> IDLE cyan
< OK IDLE
> IDENTIFY timeout=10000 prompt=blue nonce=3f9a...
< EVT TOUCH state=down
< EVT NOMATCH
< EVT TOUCH state=up
< EVT TOUCH state=down
< EVT MATCH slot=1 score=143
< OK IDENTIFY slot=1 score=143 mac=8c1e...
```

### Test vectors

`docs/protocol-vectors.json` pins the identify signature: a fixed device key,
nonce and slot, the exact material string `IDENTIFY|<nonce>|<slot>`, and its
HMAC-SHA256. `scripts/gen-vectors.py` regenerates it and `--check` fails if
the file is stale. The Swift verifier is tested against it; the firmware
must produce the same bytes, so any change to the construction starts here.

## Control socket (mactouchd <-> CLI, PAM, UI)

Path: `~/Library/Application Support/MacTouch/control.sock`, mode 0600.
The daemon is the only process that holds the serial port. Clients send one
command line and read lines until `ok` or `err`; `events` streams until the
client disconnects. Several clients may be connected at once; long commands
are one at a time and a second gets `err ... reason=busy`.

| command | response |
| -- | -- |
| `status` | `ok status proto=1 device=connected\|absent sensor=... prints=N ring=... layers=idle,privacy monitors=lock,focus,mic,camera [focus=assertions\|menubar]` |
| `led <mode> [<colour>] [<colour2>]` | `ok led` (sets the notify layer with no expiry) |
| `notify <colour> for=<seconds> [mode=<mode>]` | `ok notify` |
| `clear` | `ok clear` (drops the notify layer) |
| `idle <colour>` | `ok idle` |
| `identify timeout=<s> [nonce=<hex32>] [reason=<text>]` | `ok identify slot=N score=S [mac=<hex64>]` or `err identify reason=...` |
| `enroll slot=<n>` | progress lines `evt enroll step=...` then `ok enroll` or `err enroll` |
| `delete slot=<n>\|all`, `slots` | as device |
| `monitor <name> on\|off` | `ok monitor` (names: lock, focus, mic, camera; persisted) |
| `events` | `evt ...` lines until disconnect. Device events pass through; the daemon adds `evt device state=connected\|absent` and `evt ring state=<mode>:<colour>` |

`identify` from the socket posts a macOS notification with the reason text so
the user knows what they are approving. PAM requests pass `nonce`, and the
daemon uses the white prompt colour for them.
