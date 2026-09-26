#!/bin/bash
# Off-device test of sparse/usr/bin/droid/sweet-charge-calibration.
#
# Stubs mcetool, dconf and date, fakes the battery sysfs directory, and walks
# the script through every phase. After every single mce write it checks that
# resume < stop still holds, since mce reads the opposite as 'charge to 100%'.
#
# Run on any Linux host: bash tests/sweet-charge-calibration.test.sh sparse/usr/bin/droid/sweet-charge-calibration
SCRIPT=$1
T=/tmp/caltest; rm -rf $T; mkdir -p $T/bin $T/psy $T/dconf
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
export PATH=$T/bin:$PATH SWEET_CALIBRATION_PSY=$T/psy

mce() { printf 'cable=%s\nmode=%s\nen=%s\ndis=%s\n' "$1" "$2" "$3" "$4" > $T/mce; }
bat() { echo "$1" > $T/psy/capacity; echo "$2" > $T/psy/status; echo "${3:-300}" > $T/psy/temp; }
key() { cat "$T/dconf$(echo /desktop/sweet/charging/$1 | tr / _)" 2>/dev/null; }
setkey() { echo "$2" > "$T/dconf$(echo /desktop/sweet/charging/$1 | tr / _)"; }
phase() { key calibration_phase | tr -d "'"; }
st() { . $T/mce; echo "$mode $en $dis"; }
run() { bash "$SCRIPT" >> $T/log 2>&1; }
DAY=86400
NOW=2000000000; echo $NOW > $T/now

echo "== 1: first run schedules the first calibration one day out"
mce connected apply-thresholds 40 50; bat 45 Discharging; setkey profile "'server'"
run
check "last set to now-29d" "[ \"$(key calibration_last)\" = \"$((NOW - 29*DAY))\" ]"
check "no phase" "[ -z \"$(key calibration_phase)\" ]"
check "mce untouched" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"

echo "== 2: a day later, server profile, starts draining"
NOW=$((NOW + DAY + 60)); echo $NOW > $T/now
run
check "phase drain" "[ \"$(key calibration_phase)\" = \"'drain'\" ]"
check "saved profile values" "[ \"$(key calibration_saved)\" = \"'apply-thresholds 40 50'\" ]"
check "mce 12-14" "[ \"$(st)\" = 'apply-thresholds 12 14' ]"

echo "== 3: still draining at 30%"
bat 30 Discharging; run
check "still drain" "[ \"$(key calibration_phase)\" = \"'drain'\" ]"

echo "== 4: reaches 13%, switches to uninterrupted charge"
bat 13 Discharging; run
check "phase charge" "[ \"$(key calibration_phase)\" = \"'charge'\" ]"
check "mce enable" "[ \"\$(st | cut -d' ' -f1)\" = enable ]"

echo "== 5: 100% displayed but not terminated yet: keeps charging"
bat 100 Charging; run
check "still charge" "[ \"$(key calibration_phase)\" = \"'charge'\" ]"

echo "== 6: charger terminates: profile restored, last updated"
bat 100 Full; NOW=$((NOW + 3600)); echo $NOW > $T/now; run
check "phase cleared" "[ -z \"$(phase)\" ]"
check "mce back to 40-50" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "last = now" "[ \"$(key calibration_last)\" = \"$NOW\" ]"

echo "== 7: daily profile: no drain, charge to full directly"
NOW=$((NOW + 31*DAY)); echo $NOW > $T/now
mce connected apply-thresholds 75 80; bat 60 Charging; setkey profile "'daily'"
run
check "phase charge" "[ \"$(key calibration_phase)\" = \"'charge'\" ]"
check "limits untouched" "[ \"$(st)\" = 'enable 75 80' ]"
bat 100 Full; run
check "restored 75-80" "[ \"$(st)\" = 'apply-thresholds 75 80' ]"

echo "== 8: server drain, charger pulled: restored, retried later"
NOW=$((NOW + 31*DAY)); echo $NOW > $T/now; last_before=$(key calibration_last)
mce connected apply-thresholds 50 60; bat 55 Discharging; setkey profile "'server_reserve'"
run
check "draining" "[ \"$(st)\" = 'apply-thresholds 12 14' ]"
mce disconnected apply-thresholds 12 14; run
check "restored 50-60" "[ \"$(st)\" = 'apply-thresholds 50 60' ]"
check "last unchanged" "[ \"$(key calibration_last)\" = \"$last_before\" ]"

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
setkey calibration_interval_days "30.0"; setkey calibration_last "int64 $((NOW - 31*DAY))"
mce connected apply-thresholds 40 50; bat 45 Discharging; setkey profile "'server'"
run
check "started despite typed values" "[ \"$(key calibration_phase)\" = \"'drain'\" ]"

echo "== 14: drain timeout after 7 days"
NOW=$((NOW + 8*DAY)); echo $NOW > $T/now; bat 30 Discharging; run
check "restored" "[ \"$(st)\" = 'apply-thresholds 40 50' ]"
check "postponed to next interval" "[ \"$(key calibration_last)\" = \"$NOW\" ]"

echo "== limit ordering"
check "no resume>=stop state after any write" "[ ! -s $T/violations ]"
[ -s $T/violations ] && cat $T/violations
echo "== script log"; cat $T/log
[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
