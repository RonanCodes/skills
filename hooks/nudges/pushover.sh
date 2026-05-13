# hooks/nudges/pushover.sh
#
# Nudge: Pushover notifications for AFK / night-shift end-of-run pings.
# Satisfied when both PUSHOVER_APP_TOKEN and PUSHOVER_USER_KEY are set
# in ~/.claude/.env (sourced by nudge-check.sh before this file is read).

NUDGE_NAME="pushover"
NUDGE_SUMMARY="Push notifications when an AFK / night-shift run ends, so you know when the agent has stopped"
NUDGE_SETUP_HINT="Sign up at https://pushover.net (free for personal use, \$5 one-time per platform after a 30-day trial). Grab your user key from the dashboard at https://pushover.net/ and create an app token at https://pushover.net/apps/build. Then add PUSHOVER_APP_TOKEN=... and PUSHOVER_USER_KEY=... to ~/.claude/.env. After that /ro:pushover fires automatically at the end of AFK / night-shift runs."

nudge_check() {
  [[ -n "${PUSHOVER_APP_TOKEN:-}" && -n "${PUSHOVER_USER_KEY:-}" ]]
}
