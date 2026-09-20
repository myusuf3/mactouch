#define __STDC_WANT_LIB_EXT1__ 1
// pam_mactouch: `auth sufficient pam_mactouch.so` makes sudo, or the lock
// screen, accept a fingerprint. Anything short of a verified signature
// returns PAM_IGNORE so the stack falls through to the password. When the
// caller already collected a password (loginwindow's use_first_pass stacks)
// the module steps aside at once, so typing a password never waits on the
// ring; an empty field submitted with Return is what asks for the touch.
#define PAM_SM_AUTH
#include <security/pam_appl.h>
#include <security/pam_modules.h>

#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>

#include "approve.h"

#define MT_KEY_DIR "/etc/mactouch"
#define MT_TIMEOUT_S 20

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
  (void)flags; (void)argc; (void)argv;
  const char *authtok = NULL;
  if (pam_get_item(pamh, PAM_AUTHTOK, (const void **)&authtok) == PAM_SUCCESS && authtok && *authtok) return PAM_IGNORE;

  const char *user = NULL;
  if (pam_get_user(pamh, &user, NULL) != PAM_SUCCESS || !user || !*user) return PAM_IGNORE;
  if (strchr(user, '/') || strstr(user, "..")) return PAM_IGNORE;
  struct passwd *pw = getpwnam(user);
  if (!pw || !pw->pw_dir) return PAM_IGNORE;

  char key_path[256], socket_path[1024];
  snprintf(key_path, sizeof key_path, MT_KEY_DIR "/%s.key", user);
  snprintf(socket_path, sizeof socket_path, "%s/Library/Application Support/MacTouch/control.sock", pw->pw_dir);

  uint8_t key[MT_KEY_LEN];
  if (!mt_read_key_file(key_path, key)) return PAM_IGNORE;  // not paired: silent password fallback

  const char *service = NULL;
  pam_get_item(pamh, PAM_SERVICE, (const void **)&service);
  if (!service) service = "sudo";
  char reason[96];
  snprintf(reason, sizeof reason, "%s asked for your fingerprint", service);

  char err[MT_ERR_LEN];
  mt_result_t result = mt_request_approval(socket_path, key, MT_TIMEOUT_S, reason, err);
  memset_s(key, sizeof key, 0, sizeof key);

  switch (result) {
  case MT_APPROVED:
    syslog(LOG_AUTH | LOG_INFO, "pam_mactouch: fingerprint approved %s for %s", user, service);
    return PAM_SUCCESS;
  case MT_DENIED:
    syslog(LOG_AUTH | LOG_WARNING, "pam_mactouch: rejected %s for %s: %s", user, service, err);
    return PAM_AUTH_ERR;
  default:
    syslog(LOG_AUTH | LOG_NOTICE, "pam_mactouch: password fallback for %s: %s", user, err);
    return PAM_IGNORE;
  }
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
  (void)pamh; (void)flags; (void)argc; (void)argv;
  return PAM_SUCCESS;
}
