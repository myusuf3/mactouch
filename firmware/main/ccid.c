#include "ccid.h"

#include <string.h>

#include "device/usbd_pvt.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "tusb.h"

#include "piv.h"
#include "usb_descriptors.h"

static const char *TAG = "ccid";

// CCID rev 1.1 message types.
enum {
  PC_TO_RDR_ICC_POWER_ON = 0x62,
  PC_TO_RDR_ICC_POWER_OFF = 0x63,
  PC_TO_RDR_GET_SLOT_STATUS = 0x65,
  PC_TO_RDR_XFR_BLOCK = 0x6F,
  PC_TO_RDR_GET_PARAMETERS = 0x6C,
  PC_TO_RDR_RESET_PARAMETERS = 0x6D,
  PC_TO_RDR_SET_PARAMETERS = 0x61,
  PC_TO_RDR_ESCAPE = 0x6B,
  PC_TO_RDR_ICC_CLOCK = 0x6E,
  PC_TO_RDR_T0_APDU = 0x6A,
  PC_TO_RDR_SECURE = 0x69,
  PC_TO_RDR_MECHANICAL = 0x71,
  PC_TO_RDR_ABORT = 0x72,
  PC_TO_RDR_SET_DATA_RATE = 0x73,
  RDR_TO_PC_DATA_BLOCK = 0x80,
  RDR_TO_PC_SLOT_STATUS = 0x81,
  RDR_TO_PC_PARAMETERS = 0x82,
};

// bStatus: bits 0-1 are the ICC state, bits 6-7 the command state.
#define ICC_PRESENT_ACTIVE 0x00
#define ICC_PRESENT_INACTIVE 0x01
#define CMD_OK 0x00
#define CMD_FAILED 0x40
#define CMD_TIME_EXTENSION 0x80
#define ERR_CMD_NOT_SUPPORTED 0x00
#define ERR_ICC_MUTE 0xFE

#define CCID_HEADER 10

typedef struct {
  uint8_t type;
  uint32_t length;
  uint8_t slot;
  uint8_t seq;
  uint8_t param[3];
  uint8_t data[CCID_MAX_MESSAGE - CCID_HEADER];
} __attribute__((packed)) ccid_message_t;

// T=1 protocol parameters as the host reads them back; the values are the
// ones the ATR below advertises.
static const uint8_t t1_parameters[7] = {0x18, 0x10, 0x00, 0x45, 0x00, 0xFE, 0x00};

// ATR for a T=1 card with "mactouch" as historical bytes; the checksum is
// filled in at init.
static uint8_t atr[] = {0x3B, 0xD8, 0x18, 0xFF, 0x81, 0xB1, 0xFE, 0x45, 0x1F, 0x03,
                        'm', 'a', 'c', 't', 'o', 'u', 'c', 'h', 0x00};

static uint8_t itf_num;
static uint8_t ep_out, ep_in;
static bool mounted;
static bool powered;
static CFG_TUSB_MEM_SECTION CFG_TUSB_MEM_ALIGN uint8_t out_buffer[CFG_TUD_ENDPOINT0_SIZE];
static CFG_TUSB_MEM_SECTION CFG_TUSB_MEM_ALIGN ccid_message_t inbound;
static CFG_TUSB_MEM_SECTION CFG_TUSB_MEM_ALIGN ccid_message_t outbound;
static uint32_t inbound_len;
static bool zlp_pending;
static QueueHandle_t requests;
static uint8_t current_seq;

// MARK: responses, sent from the CCID task

// A reply that fills its last packet exactly needs a zero-length packet
// after it, or the host keeps waiting for more; sent from the IN completion.
static void send(const ccid_message_t *reply) {
  uint32_t total = CCID_HEADER + reply->length;
  if (!usbd_edpt_claim(0, ep_in)) return;
  memcpy(&outbound, reply, total);
  zlp_pending = total % CFG_TUD_ENDPOINT0_SIZE == 0;
  usbd_edpt_xfer(0, ep_in, (uint8_t *)&outbound, (uint16_t)total);
}

static void reply_slot_status(uint8_t seq, uint8_t status, uint8_t error) {
  ccid_message_t reply = {.type = RDR_TO_PC_SLOT_STATUS, .length = 0, .slot = 0, .seq = seq};
  reply.param[0] = status;
  reply.param[1] = error;
  reply.param[2] = 0;
  send(&reply);
}

// Tells the host the card is still working, so it resets its timeout. Sent
// while the card waits for a finger; bError carries the multiplier.
void ccid_time_extension(void) {
  ccid_message_t reply = {.type = RDR_TO_PC_DATA_BLOCK, .length = 0, .slot = 0, .seq = current_seq};
  reply.param[0] = ICC_PRESENT_ACTIVE | CMD_TIME_EXTENSION;
  reply.param[1] = 1;
  reply.param[2] = 0;
  send(&reply);
}

static void reply_data_block(uint8_t seq, const uint8_t *data, uint32_t len) {
  ccid_message_t reply = {.type = RDR_TO_PC_DATA_BLOCK, .length = len, .slot = 0, .seq = seq};
  reply.param[0] = ICC_PRESENT_ACTIVE | CMD_OK;
  reply.param[1] = 0;
  reply.param[2] = 0;
  memcpy(reply.data, data, len);
  send(&reply);
}

static void reply_parameters(uint8_t seq) {
  ccid_message_t reply = {.type = RDR_TO_PC_PARAMETERS, .length = sizeof(t1_parameters), .slot = 0, .seq = seq};
  reply.param[0] = ICC_PRESENT_ACTIVE | CMD_OK;
  reply.param[1] = 0;
  reply.param[2] = 0x01;  // T=1
  memcpy(reply.data, t1_parameters, sizeof(t1_parameters));
  send(&reply);
}

static void handle(const ccid_message_t *msg) {
  if (msg->slot != 0) {
    reply_slot_status(msg->seq, CMD_FAILED | 0x02, 0x05);  // slot does not exist
    return;
  }
  switch (msg->type) {
    case PC_TO_RDR_ICC_POWER_ON:
      powered = true;
      reply_data_block(msg->seq, atr, sizeof(atr));
      break;
    case PC_TO_RDR_ICC_POWER_OFF:
      powered = false;
      piv_session_reset();
      reply_slot_status(msg->seq, ICC_PRESENT_INACTIVE | CMD_OK, 0);
      break;
    case PC_TO_RDR_GET_SLOT_STATUS:
      reply_slot_status(msg->seq, (powered ? ICC_PRESENT_ACTIVE : ICC_PRESENT_INACTIVE) | CMD_OK, 0);
      break;
    case PC_TO_RDR_XFR_BLOCK: {
      if (!powered) {
        reply_slot_status(msg->seq, ICC_PRESENT_INACTIVE | CMD_FAILED, ERR_ICC_MUTE);
        break;
      }
      static uint8_t response[CCID_MAX_MESSAGE - CCID_HEADER];
      current_seq = msg->seq;
      size_t n = piv_apdu(msg->data, msg->length, response, sizeof(response));
      reply_data_block(msg->seq, response, (uint32_t)n);
      break;
    }
    case PC_TO_RDR_GET_PARAMETERS:
    case PC_TO_RDR_RESET_PARAMETERS:
    case PC_TO_RDR_SET_PARAMETERS:
      reply_parameters(msg->seq);
      break;
    case PC_TO_RDR_ABORT:
      reply_slot_status(msg->seq, ICC_PRESENT_ACTIVE | CMD_OK, 0);
      break;
    default:
      reply_slot_status(msg->seq, ICC_PRESENT_ACTIVE | CMD_FAILED, ERR_CMD_NOT_SUPPORTED);
      break;
  }
}

static void ccid_task(void *arg) {
  (void)arg;
  static ccid_message_t msg;
  for (;;) {
    if (xQueueReceive(requests, &msg, portMAX_DELAY) == pdTRUE) handle(&msg);
  }
}

// MARK: TinyUSB class driver, runs on the USB task

static void driver_init(void) {}

static bool driver_deinit(void) { return true; }

static void driver_reset(uint8_t rhport) {
  (void)rhport;
  mounted = false;
  powered = false;
  inbound_len = 0;
  zlp_pending = false;
  piv_session_reset();
}

static void arm_out(void) {
  usbd_edpt_xfer(0, ep_out, out_buffer, sizeof(out_buffer));
}

static uint16_t driver_open(uint8_t rhport, tusb_desc_interface_t const *desc_intf, uint16_t max_len) {
  if (desc_intf->bInterfaceClass != TUSB_CLASS_SMART_CARD) return 0;
  uint16_t const needed = sizeof(tusb_desc_interface_t) + CCID_CLASS_DESC_LEN + 2 * sizeof(tusb_desc_endpoint_t);
  TU_VERIFY(max_len >= needed, 0);
  itf_num = desc_intf->bInterfaceNumber;

  uint8_t const *p = (uint8_t const *)desc_intf + sizeof(tusb_desc_interface_t);
  p = tu_desc_next(p);  // the CCID class descriptor
  for (int i = 0; i < 2; i++) {
    tusb_desc_endpoint_t const *ep = (tusb_desc_endpoint_t const *)p;
    TU_ASSERT(ep->bDescriptorType == TUSB_DESC_ENDPOINT, 0);
    TU_ASSERT(usbd_edpt_open(rhport, ep), 0);
    if (tu_edpt_dir(ep->bEndpointAddress) == TUSB_DIR_IN) ep_in = ep->bEndpointAddress; else ep_out = ep->bEndpointAddress;
    p = tu_desc_next(p);
  }
  mounted = true;
  arm_out();
  ESP_LOGI(TAG, "reader up on interface %u", itf_num);
  return needed;
}

static bool driver_control_xfer(uint8_t rhport, uint8_t stage, tusb_control_request_t const *request) {
  // CCID class requests (abort, clock frequencies, data rates) are optional;
  // the descriptor advertises none, so anything here is a stall.
  (void)rhport; (void)stage; (void)request;
  return false;
}

static bool driver_xfer(uint8_t rhport, uint8_t ep_addr, xfer_result_t result, uint32_t xferred) {
  (void)rhport;
  if (result != XFER_RESULT_SUCCESS) return true;
  if (ep_addr == ep_in) {
    if (zlp_pending) {
      zlp_pending = false;
      if (usbd_edpt_claim(0, ep_in)) usbd_edpt_xfer(0, ep_in, NULL, 0);
    }
    return true;
  }

  if (inbound_len + xferred <= sizeof(inbound)) {
    memcpy((uint8_t *)&inbound + inbound_len, out_buffer, xferred);
    inbound_len += xferred;
  } else {
    inbound_len = 0;  // oversized message: drop it and start over
  }
  // A message is complete when the header has arrived and dwLength bytes
  // followed it. A zero-length packet after a full message is ignored.
  if (inbound_len >= CCID_HEADER) {
    uint32_t total = CCID_HEADER + inbound.length;
    if (total > sizeof(inbound)) {
      inbound_len = 0;
    } else if (inbound_len >= total) {
      if (xQueueSend(requests, &inbound, 0) != pdTRUE) ESP_LOGW(TAG, "request dropped, task busy");
      inbound_len = 0;
    }
  }
  arm_out();
  return true;
}

static usbd_class_driver_t const ccid_driver = {
  .name = "CCID",
  .init = driver_init,
  .deinit = driver_deinit,
  .reset = driver_reset,
  .open = driver_open,
  .control_xfer_cb = driver_control_xfer,
  .xfer_cb = driver_xfer,
  .sof = NULL,
};

usbd_class_driver_t const *usbd_app_driver_get_cb(uint8_t *driver_count) {
  *driver_count = 1;
  return &ccid_driver;
}

bool ccid_mounted(void) { return mounted; }

void ccid_init(void) {
  uint8_t tck = 0;
  for (size_t i = 1; i < sizeof(atr) - 1; i++) tck ^= atr[i];
  atr[sizeof(atr) - 1] = tck;
  requests = xQueueCreate(2, sizeof(ccid_message_t));
  configASSERT(requests);
  configASSERT(xTaskCreate(ccid_task, "ccid", 6144, NULL, 3, NULL) == pdPASS);
}
