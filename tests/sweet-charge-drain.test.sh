#!/bin/sh
# Test of sparse/usr/bin/droid/sweet-charge-drain (the root side of the
# calibration drain) against a fake sysfs.
#
# Fakes battery/capacity and battery/input_suspend under SWEET_DRAIN_PSY, puts
# the request and root's state in a fresh mktemp directory, fakes the clock
# through SWEET_DRAIN_NOW, and walks the script through its safety rules.
# Touches nothing real.
#
# Runs under busybox ash, which is the phone's /bin/sh, so it can run on the
# phone itself or on any Linux host with busybox:
#   busybox ash tests/sweet-charge-drain.test.sh sparse/usr/bin/droid/sweet-charge-drain
# The checks are eval'd strings, single-quoted on purpose; $T is a mktemp path.
# shellcheck disable=SC2016,SC2086,SC2034
SCRIPT=$1
SHELL_UNDER_TEST=${SHELL_UNDER_TEST:-busybox ash}
T=$(mktemp -d) || exit 2
mkdir -p $T/psy $T/req $T/state
fail=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1   ($2)"; fail=1; fi; }

export SWEET_DRAIN_PSY=$T/psy SWEET_DRAIN_REQUEST=$T/req/request SWEET_DRAIN_STATE=$T/state
NOW=2000000000
DAY=86400
step() { SWEET_DRAIN_NOW=$NOW $SHELL_UNDER_TEST "$SCRIPT" --step > $T/out 2>&1; }
susp() { cat $T/psy/input_suspend; }
want() { echo "$1" > $T/req/request; }
cap() { echo "$1" > $T/psy/capacity; }

echo 0 > $T/psy/input_suspend; cap 50

echo "no request file"
step; rc=$?
check "released, not holding" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'

echo "request on"
want on; step; rc=$?
check "holds input_suspend=1" '[ $rc = 0 ] && [ "$(susp)" = 1 ]'
check "logs the hold once" 'grep -q "draining from 50%" $T/out'
check "start time kept in root state" '[ "$(cat $T/state/started)" = $NOW ]'
NOW=$((NOW + 60)); step; rc=$?
check "still holding a minute later" '[ $rc = 0 ] && [ "$(susp)" = 1 ]'
check "quiet while holding" '[ ! -s $T/out ]'

echo "something reset input_suspend while holding"
echo 0 > $T/psy/input_suspend; step; rc=$?
check "held again" '[ $rc = 0 ] && [ "$(susp)" = 1 ]'

echo "request off"
want off; step; rc=$?
check "released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
check "root state cleared" '[ ! -e $T/state/started ]'

echo "request missing while holding"
want on; step; rm -f $T/req/request; step; rc=$?
check "released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'

echo "anything but the literal on"
for w in 'On' 'on ' 'yes' '1' 'on; rm -rf /' ''; do
    want on; step
    printf '%s' "$w" > $T/req/request; step; rc=$?
    check "'$w' releases" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
done
check "request content never logged" '! grep -q "rm -rf" $T/out'

echo "request is a symlink to a file saying on"
echo on > $T/elsewhere; rm -f $T/req/request; ln -s $T/elsewhere $T/req/request
step; rc=$?
check "not followed, released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
rm -f $T/req/request

echo "request is a directory"
mkdir $T/req/request; step; rc=$?
check "released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
rmdir $T/req/request

echo "huge request file: only 16 bytes read"
dd if=/dev/zero of=$T/req/request bs=1024 count=4096 2>/dev/null
step; rc=$?
check "released, finished" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
{ echo on; yes x | head -c 4194304; } > $T/req/request
step; rc=$?
check "on followed by junk is not on" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'

echo "battery at 11% still drains, at 10% released"
want on; cap 11; step; rc=$?
check "holding at 11%" '[ $rc = 0 ] && [ "$(susp)" = 1 ]'
cap 10; step; rc=$?
check "released at 10%" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
check "says why" 'grep -q "battery at 10%" $T/out'
cap 14; step; rc=$?
check "not held again while the request still says on" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
want off; step; want on; step; rc=$?
check "a new request after off holds again" '[ $rc = 0 ] && [ "$(susp)" = 1 ]'

echo "capacity unreadable"
rm -f $T/psy/capacity; step; rc=$?
check "released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
cap junk; want off; step; want on; step; rc=$?
check "garbage capacity: released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
cap 50; want off; step

echo "7 days"
want on; step
NOW=$((NOW + 7 * DAY - 1)); step; rc=$?
check "still holding just before 7 days" '[ $rc = 0 ] && [ "$(susp)" = 1 ]'
NOW=$((NOW + 1)); step; rc=$?
check "released at 7 days" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
check "says why" 'grep -q "7 days" $T/out'
want on; NOW=$((NOW + 60)); step; rc=$?
check "rewriting on does not restart the clock" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
want off; step

echo "bad root state"
want on; echo junk > $T/state/started; step; rc=$?
check "released" '[ $rc = 1 ] && [ "$(susp)" = 0 ]'
want off; step

echo "--release (ExecStopPost)"
want on; step; $SHELL_UNDER_TEST "$SCRIPT" --release
check "released" '[ "$(susp)" = 0 ]'

echo "--boot"
want on; step
$SHELL_UNDER_TEST "$SCRIPT" --boot > $T/out 2>&1
check "released" '[ "$(susp)" = 0 ]'
check "request dropped" '[ ! -e $T/req/request ]'
check "root state cleared" '[ ! -e $T/state/started ] && [ ! -e $T/state/released ]'
echo on > $T/elsewhere; ln -s $T/elsewhere $T/req/request
$SHELL_UNDER_TEST "$SCRIPT" --boot > $T/out 2>&1
check "a symlinked request is removed, its target kept" '[ ! -L $T/req/request ] && [ "$(cat $T/elsewhere)" = on ]'

echo "unknown argument"
$SHELL_UNDER_TEST "$SCRIPT" --bogus 2>/dev/null; rc=$?
check "exit 2, nothing held" '[ $rc = 2 ] && [ "$(susp)" = 0 ]'

echo "input_suspend cannot be written"
want on; mv $T/psy/input_suspend $T/psy/is.bak; mkdir $T/psy/input_suspend
step; rc=$?
check "gives up instead of claiming a hold" '[ $rc = 1 ] && grep -q "could not write" $T/out'
rmdir $T/psy/input_suspend; mv $T/psy/is.bak $T/psy/input_suspend; want off; step

echo "service loop: holds, ends on stop"
want on
$SHELL_UNDER_TEST "$SCRIPT" > $T/loop.out 2>&1 &
pid=$!
i=0; while [ "$(susp)" != 1 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
check "holding" '[ "$(susp)" = 1 ] && kill -0 $pid'
kill -TERM $pid; wait $pid
check "SIGTERM releases at once" '[ "$(susp)" = 0 ]'

echo "service loop: nothing requested, exits released"
want off; echo 1 > $T/psy/input_suspend
$SHELL_UNDER_TEST "$SCRIPT" > $T/loop.out 2>&1; rc=$?
check "exit 0, released" '[ $rc = 0 ] && [ "$(susp)" = 0 ]'

rm -rf $T
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
