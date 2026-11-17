#!/bin/bash
# Off-device test of sparse/usr/bin/droid/sweet-charge-calibration.
#
# Stubs mcetool and dconf, fakes the clock through SWEET_CALIBRATION_NOW (busybox
# runs its own date applet, so a PATH stub would be ignored), fakes the battery sysfs directory, and walks
# the script through every phase. After every single mce write it checks that
# resume < stop still holds, since mce reads the opposite as 'charge to 100%'.
# The drain request for the root helper (sweet-charge-drain) goes to a
# directory in the test tree; the test checks it is 'on' exactly while a drain
# is running.
#
# Run on any Linux host: bash tests/sweet-charge-calibration.test.sh sparse/usr/bin/droid/sweet-charge-calibration
SCRIPT=$1
# The phone's /bin/sh and /bin/bash are both busybox ash, so test under that by
# default: GNU bash accepts syntax (like <<<) that fails to parse on the phone.
SHELL_UNDER_TEST=${SHELL_UNDER_TEST:-busybox ash}
$SHELL_UNDER_TEST -c true 2>/dev/null || { echo "cannot run '$SHELL_UNDER_TEST' (install busybox)"; exit 2; }
T=/tmp/caltest; rm -rf $T; mkdir -p $T/bin $T/psy $T/dconf $T/drain
fail=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1   ($2)"; fail=1; fi; }

# ---- stubs --------------------------------------------------------------
cat > $T/bin/date <<'EOF'
#!/bin/bash
[ "$1" = "+%s" ] && { cat /tmp/caltest/now; exit; }
exec /bin/date "$@"
EOF
cat > $T/bin/dconf <<'EOF'
#!/bin/bash
D=/tmp/caltest/dconf
case "$1" in
read)  f="$D$(echo "$2" | tr / _)"; [ -f "$f" ] && cat "$f" ;;
write) echo "$3" > "$D$(echo "$2" | tr / _)" ;;
reset) rm -f "$D$(echo "$2" | tr / _)" ;;
esac
EOF
cat > $T/bin/mcetool <<'EOF'
#!/bin/bash
S=/tmp/caltest/mce; . $S
if [ $# -eq 0 ]; then
  printf 'Charger cable:                       %s\n' "$cable"
  printf 'Charging mode:                       %s\n' "$mode"
  printf 'Charging enable limit:               %s (%%)\n' "$en"
  printf 'Charging disable limit:              %s (%%)\n' "$dis"
  exit 0
fi
for a in "$@"; do
  case "$a" in
  --set-charging-mode=*)          mode=${a#*=} ;;
  --set-charging-enable-limit=*)  en=${a#*=} ;;
  --set-charging-disable-limit=*) dis=${a#*=} ;;
  esac
  echo "$a" >> /tmp/caltest/calls
  # Invariant after every single write: resume < stop.
  [ "$en" -lt "$dis" ] || echo "VIOLATION after $a: en=$en dis=$dis" >> /tmp/caltest/violations
done
printf 'cable=%s\nmode=%s\nen=%s\ndis=%s\n' "$cable" "$mode" "$en" "$dis" > $S
EOF
chmod +x $T/bin/*
export PATH=$T/bin:$PATH SWEET_CALIBRATION_PSY=$T/psy SWEET_CALIBRATION_DRAIN_REQUEST=$T/drain/request

mce() { printf 'cable=%s\nmode=%s\nen=%s\ndis=%s\n' "$1" "$2" "$3" "$4" > $T/mce; }
bat() { echo "$1" > $T/psy/capacity; echo "$2" > $T/psy/status; echo "${3:-300}" > $T/psy/temp; }
key() { cat "$T/dconf$(echo /desktop/sweet/charging/$1 | tr / _)" 2>/dev/null; }
setkey() { echo "$2" > "$T/dconf$(echo /desktop/sweet/charging/$1 | tr / _)"; }
phase() { key calibration_phase | tr -d "'"; }
st() { . $T/mce; echo "$mode $en $dis"; }
req() { cat $T/drain/request 2>/dev/null; }
run() { SWEET_CALIBRATION_NOW=$(cat $T/now) $SHELL_UNDER_TEST "$SCRIPT" >> $T/log 2>&1; }
DAY=86400
NOW=2000000000; echo $NOW > $T/now

echo "== 1: first run schedules the first calibration one day out, no fake last"
mce connected apply-thresholds 40 50; bat 45 Discharging; setkey profile "'server'"
run
check "next = now+1d" "[ \"$(key calibration_next)\" = \"$((NOW + DAY))\" ]"
check "last not set" "[ -z \"$(key calibration_last)\" ]"
check "no phase" "[ -z \"$(key calibration_phase)\" ]"
check "mce untouched" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "no drain request written" "[ ! -e $T/drain/request ]"

echo "== 2: a day later, server profile, starts draining"
NOW=$((NOW + DAY + 60)); echo $NOW > $T/now
run
check "phase drain" "[ \"$(key calibration_phase)\" = \"'drain'\" ]"
check "saved profile values" "[ \"$(key calibration_saved)\" = \"'apply-thresholds 40 50'\" ]"
check "mce 12-14" "[ \"$(st)\" = 'apply-thresholds 12 14' ]"
check "drain requested" "[ \"$(req)\" = on ]"
check "no temp file left" "[ -z \"$(ls $T/drain | grep -v '^request$')\" ]"

echo "== 3: still draining at 30%"
bat 30 Discharging; run
check "still drain" "[ \"$(key calibration_phase)\" = \"'drain'\" ]"
check "drain still requested" "[ \"$(req)\" = on ]"

echo "== 4: reaches 13%, switches to uninterrupted charge"
bat 13 Discharging; run
check "phase charge" "[ \"$(key calibration_phase)\" = \"'charge'\" ]"
check "mce enable" "[ \"\$(st | cut -d' ' -f1)\" = enable ]"
check "drain request off before charging" "[ \"$(req)\" = off ]"

echo "== 5: 100% displayed but not terminated yet: keeps charging"
bat 100 Charging; run
check "still charge" "[ \"$(key calibration_phase)\" = \"'charge'\" ]"

echo "== 6: charger terminates: profile restored, last and next updated"
bat 100 Full; NOW=$((NOW + 3600)); echo $NOW > $T/now; run
check "phase cleared" "[ -z \"$(phase)\" ]"
check "mce back to 40-50" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "last = now" "[ \"$(key calibration_last)\" = \"$NOW\" ]"
check "next = now+30d" "[ \"$(key calibration_next)\" = \"$((NOW + 30*DAY))\" ]"

echo "== 7: daily profile: no drain, charge to full directly"
NOW=$((NOW + 31*DAY)); echo $NOW > $T/now
mce connected apply-thresholds 75 80; bat 60 Charging; setkey profile "'daily'"
run
check "phase charge" "[ \"$(key calibration_phase)\" = \"'charge'\" ]"
check "limits untouched" "[ \"$(st)\" = 'enable 75 80' ]"
bat 100 Full; run
check "restored 75-80" "[ \"$(st)\" = 'apply-thresholds 75 80' ]"

echo "== 8: server drain, charger pulled: restored, retried later"
NOW=$((NOW + 31*DAY)); echo $NOW > $T/now; last_before=$(key calibration_last); next_before=$(key calibration_next)
mce connected apply-thresholds 50 60; bat 55 Discharging; setkey profile "'server_reserve'"
run
check "draining" "[ \"$(st)\" = 'apply-thresholds 12 14' ]"
check "drain requested" "[ \"$(req)\" = on ]"
mce disconnected apply-thresholds 12 14; run
check "restored 50-60" "[ \"$(st)\" = 'apply-thresholds 50 60' ]"
check "drain request off" "[ \"$(req)\" = off ]"
check "last unchanged" "[ \"$(key calibration_last)\" = \"$last_before\" ]"
check "next unchanged, retried when plugged in" "[ \"$(key calibration_next)\" = \"$next_before\" ]"

echo "== 9: too hot: waits"
mce connected apply-thresholds 50 60; bat 55 Discharging 470; run
check "not started" "[ -z \"$(phase)\" ]"

echo "== 10: disabled: does nothing"
setkey calibration_enabled false; bat 55 Discharging 300; run
check "not started" "[ -z \"$(phase)\" ]"
setkey calibration_enabled true

echo "== 11: 'always charge' mode (Full charge profile): not started"
mce connected enable 50 60; run
check "not started" "[ -z \"$(phase)\" ]"

echo "== 12: natural full charge counts as a calibration"
bat 100 Full; run
check "last = now" "[ \"$(key calibration_last)\" = \"$NOW\" ]"

echo "== 13: dconf quirks: typed and double values"
NOW=$((NOW + 31*DAY)); echo $NOW > $T/now
setkey calibration_interval_days "30.0"; setkey calibration_next "int64 $((NOW - DAY))"
mce connected apply-thresholds 40 50; bat 45 Discharging; setkey profile "'server'"
run
check "started despite typed values" "[ \"$(key calibration_phase)\" = \"'drain'\" ]"
check "drain requested" "[ \"$(req)\" = on ]"

echo "== 14: drain timeout after 7 days"
NOW=$((NOW + 8*DAY)); echo $NOW > $T/now; bat 30 Discharging; last_before=$(key calibration_last); run
check "restored" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "postponed one interval" "[ \"$(key calibration_next)\" = \"$((NOW + 30*DAY))\" ]"
check "a timeout is not a calibration" "[ \"$(key calibration_last)\" = \"$last_before\" ]"
check "drain request off" "[ \"$(req)\" = off ]"

echo "== 15: upgrade from the first release: the back-dated last is dropped"
dconf reset /desktop/sweet/charging/calibration_next
setkey calibration_last "$((NOW - 29*DAY))"; bat 45 Discharging; run
check "fake last removed" "[ -z \"$(key calibration_last)\" ]"
check "next = now+1d" "[ \"$(key calibration_next)\" = \"$((NOW + DAY))\" ]"
check "not started early" "[ -z \"$(phase)\" ]"

echo "== 16: completion schedules by the configured interval"
setkey calibration_interval_days 14; setkey calibration_next 0
mce connected apply-thresholds 75 80; bat 60 Charging; setkey profile "'daily'"; run
check "started when due" "[ \"$(phase)\" = charge ]"
bat 100 Full; run
check "next = now+14d" "[ \"$(key calibration_next)\" = \"$((NOW + 14*DAY))\" ]"

echo "== 17: drain stopped on the Settings page: request off at the next check"
NOW=$((NOW + 15*DAY)); echo $NOW > $T/now
mce connected apply-thresholds 40 50; bat 45 Discharging; setkey profile "'server'"; run
check "draining" "[ \"$(phase)\" = drain ] && [ \"$(req)\" = on ]"
# What the page's Stop does: clear phase and saved, restore the profile itself.
setkey calibration_phase "''"; setkey calibration_saved "''"; mce connected apply-thresholds 40 50
setkey calibration_next $((NOW + 30*DAY)); run
check "drain request off" "[ \"$(req)\" = off ]"
check "not started again" "[ -z \"$(phase)\" ]"
check "profile left as the page set it" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
touch -d @1 $T/drain/request; run
check "off is not rewritten on every check" "[ \"$(stat -c %Y $T/drain/request)\" = 1 ]"

echo "== 18: calibration switched off on the page during a drain: request off"
setkey calibration_next 0; run
check "draining" "[ \"$(phase)\" = drain ] && [ \"$(req)\" = on ]"
setkey calibration_phase "''"; setkey calibration_saved "''"; mce connected apply-thresholds 40 50
setkey calibration_enabled false; run
check "drain request off" "[ \"$(req)\" = off ]"
setkey calibration_enabled true

echo "== 19: reboot during a drain (root drops the request): restored, postponed"
setkey calibration_next 0; run
check "draining" "[ \"$(phase)\" = drain ] && [ \"$(req)\" = on ]"
last_before=$(key calibration_last)
NOW=$((NOW + 3600)); echo $NOW > $T/now
rm -f $T/drain/request; bat 40 Discharging; run
check "phase cleared" "[ -z \"$(phase)\" ]"
check "restored 40-50" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "postponed one interval" "[ \"$(key calibration_next)\" = \"$((NOW + 14*DAY))\" ]"
check "not a calibration" "[ \"$(key calibration_last)\" = \"$last_before\" ]"
check "no request written back" "[ ! -e $T/drain/request ]"

echo "== 20: reboot, but already in the learning window: charges to full"
setkey calibration_next 0; bat 45 Discharging; run
check "draining" "[ \"$(phase)\" = drain ] && [ \"$(req)\" = on ]"
rm -f $T/drain/request; bat 13 Discharging; run
check "phase charge" "[ \"$(phase)\" = charge ]"
check "mce enable" "[ \"\$(st | cut -d' ' -f1)\" = enable ]"
bat 100 Full; run
check "restored 40-50" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "completed" "[ \"$(key calibration_last)\" = \"$NOW\" ]"

echo "== 21: request cannot be written (helper missing): charge to full, no drain"
setkey calibration_next 0; bat 45 Discharging
SWEET_CALIBRATION_DRAIN_REQUEST=$T/nodir/request run
check "phase charge" "[ \"$(phase)\" = charge ]"
check "mce enable, limits untouched" "[ \"$(st)\" = 'enable 40 50' ]"
check "says so" "grep -q 'cannot drain' $T/log"
bat 100 Full; run
check "restored 40-50" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"

echo "== 22: a symlinked request is not taken as 'on'"
setkey calibration_next 0; bat 45 Discharging; run
check "draining" "[ \"$(phase)\" = drain ]"
echo on > $T/elsewhere; rm -f $T/drain/request; ln -s $T/elsewhere $T/drain/request
NOW=$((NOW + 600)); echo $NOW > $T/now; run
check "treated as gone: restored" "[ -z \"$(phase)\" ] && [ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "target untouched" "[ \"$(cat $T/elsewhere)\" = on ]"
rm -f $T/drain/request

echo "== limit ordering"
check "no resume>=stop state after any write" "[ ! -s $T/violations ]"
[ -s $T/violations ] && cat $T/violations
echo "== script log"; cat $T/log
[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
