#!/bin/sh
# Test of sparse/usr/bin/droid/sweet-performance-apply against a fake sysfs.
#
# Fakes the cpufreq and kgsl files under SWEET_PERF_ROOT, stubs mcetool, and
# walks the script through every mode and transition. Touches nothing real.
#
# Runs under busybox ash, which is the phone's /bin/sh, so it can run on the
# phone itself or on any Linux host with busybox:
#   busybox ash tests/sweet-performance-apply.test.sh sparse/usr/bin/droid/sweet-performance-apply
SCRIPT=$1
SHELL_UNDER_TEST=${SHELL_UNDER_TEST:-busybox ash}
T=/tmp/perftest
rm -rf $T
mkdir -p $T/bin $T/root/sys/devices/system/cpu/cpufreq/policy0 \
         $T/root/sys/devices/system/cpu/cpufreq/policy6 $T/root/sys/class/kgsl/kgsl-3d0
fail=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1   ($2)"; fail=1; fi; }

cat > $T/bin/mcetool <<'EOF'
#!/bin/sh
S=/tmp/perftest/psm
[ -f $S ] || echo disabled > $S
if [ $# -eq 0 ]; then
    printf 'Power saving mode:                   enabled (inactive)\n'
    printf 'Forced power saving mode:            %s\n' "$(cat $S)"
    exit 0
fi
case "$1" in
--set-forced-psm=*) echo "${1#*=}" > $S; echo "$1" >> /tmp/perftest/calls ;;
esac
EOF
chmod +x $T/bin/mcetool
export PATH=$T/bin:$PATH SWEET_PERF_ROOT=$T/root \
       SWEET_PERF_MODE_FILE=$T/mode SWEET_PERF_PSM_MARK=$T/psm-mark

C=$T/root/sys/devices/system/cpu/cpufreq
G=$T/root/sys/class/kgsl/kgsl-3d0
v() { cat "$1"; }
state() { echo "$(v $C/policy0/scaling_min_freq)-$(v $C/policy0/scaling_max_freq) $(v $C/policy6/scaling_min_freq)-$(v $C/policy6/scaling_max_freq) gpu $(v $G/max_pwrlevel)/$(v $G/min_pwrlevel) psm $(cat $T/psm)"; }
run() { echo "$1" > $T/mode; $SHELL_UNDER_TEST "$SCRIPT" > $T/out 2>&1; }

# Boot defaults as read on the device.
echo 576000 > $C/policy0/scaling_min_freq; echo 1804800 > $C/policy0/scaling_max_freq
echo 652800 > $C/policy6/scaling_min_freq; echo 2304000 > $C/policy6/scaling_max_freq
echo 0 > $G/max_pwrlevel; echo 6 > $G/min_pwrlevel; echo disabled > $T/psm

BAL="576000-1804800 652800-2304000 gpu 0/6 psm disabled"

echo "balanced from boot"
run balanced
check "limits are the boot defaults" '[ "$(state)" = "$BAL" ]'

echo "performance"
run performance
check "floors raised, ceilings full" '[ "$(state)" = "1248000-1804800 1324800-2304000 gpu 0/3 psm disabled" ]'

echo "saver"
run saver
check "ceilings lowered, floors default, psm on" '[ "$(state)" = "576000-1497600 652800-1708800 gpu 2/6 psm enabled" ]'
check "psm mark written" '[ -e $T/psm-mark ]'

echo "saver -> performance"
run performance
check "psm turned off again, perf limits" '[ "$(state)" = "1248000-1804800 1324800-2304000 gpu 0/3 psm disabled" ]'
check "psm mark removed" '[ ! -e $T/psm-mark ]'

echo "forced psm set elsewhere survives balanced"
echo enabled > $T/psm; rm -f $T/calls
run balanced
check "still enabled" '[ "$(cat $T/psm)" = enabled ]'
check "mcetool not called" '[ ! -s $T/calls ]'

echo "saver while psm already forced elsewhere, then balanced"
run saver
check "no mark when psm was already on" '[ ! -e $T/psm-mark ]'
run balanced
check "psm left on" '[ "$(cat $T/psm)" = enabled ]'
echo disabled > $T/psm

echo "garbage in the mode file"
run 'saver; rm -rf /'
check "treated as balanced" '[ "$(state)" = "$BAL" ]'
check "says so" 'grep -q "using balanced" $T/out'
check "does not echo the content" '! grep -q "rm -rf" $T/out'

echo "mode file is a symlink"
echo "performance" > $T/elsewhere; ln -sf $T/elsewhere $T/mode
$SHELL_UNDER_TEST "$SCRIPT" > $T/out 2>&1
check "symlink not followed, balanced" '[ "$(state)" = "$BAL" ]'
rm -f $T/mode

echo "missing mode file"
rm -f $T/mode; $SHELL_UNDER_TEST "$SCRIPT" > $T/out 2>&1
check "balanced" '[ "$(state)" = "$BAL" ]'

echo "mode file is a directory"
mkdir $T/mode; $SHELL_UNDER_TEST "$SCRIPT" > $T/out 2>&1
check "balanced" '[ "$(state)" = "$BAL" ]'
rmdir $T/mode

echo "unwritable file does not stop the rest"
rm -f $G/max_pwrlevel; mkdir $G/max_pwrlevel
run saver
check "cpu caps still applied" '[ "$(v $C/policy6/scaling_max_freq)" = 1708800 ]'
check "failure reported" 'grep -q "could not write" $T/out'

rm -rf $T
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
