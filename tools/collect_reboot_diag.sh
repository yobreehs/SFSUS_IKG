#!/system/bin/sh
# collect_reboot_diag.sh
#
# Собирает всё, что нужно для выяснения причины внезапного ребута/софт-ребута,
# в один архив на телефоне. Требует root.
#
# Запуск прямо на телефоне (Termux):
#   su -c 'sh /path/to/collect_reboot_diag.sh'
# Или через adb:
#   adb push collect_reboot_diag.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/collect_reboot_diag.sh'
#
# Результат: /sdcard/reboot_diag/<дата_время>.tar.gz — можно забрать
# через файловый менеджер, Termux или `adb pull`.

OUT=/sdcard/reboot_diag
TS=$(date +%Y%m%d_%H%M%S)
D="$OUT/$TS"
mkdir -p "$D"

log() { echo "== $*"; }

log "meta"
{
  echo "collected_at: $(date)"
  echo "boot_reason (sys.boot.reason): $(getprop sys.boot.reason 2>/dev/null)"
  echo "boot_reason (ro.boot.bootreason): $(getprop ro.boot.bootreason 2>/dev/null)"
  echo "kernel: $(uname -r 2>/dev/null)"
  echo "uptime: $(cat /proc/uptime 2>/dev/null)"
  echo "panic: $(cat /proc/sys/kernel/panic 2>/dev/null)"
  echo "panic_on_oops: $(cat /proc/sys/kernel/panic_on_oops 2>/dev/null)"
  echo "hung_task_timeout_secs: $(cat /proc/sys/kernel/hung_task_timeout_secs 2>/dev/null)"
  echo "softlockup_panic: $(cat /proc/sys/kernel/softlockup_panic 2>/dev/null)"
} > "$D/meta.txt"
cat "$D/meta.txt"

log "pstore/ramoops (критично при панике ядра)"
mkdir -p "$D/pstore"
ls -la /sys/fs/pstore/ > "$D/pstore/_listing.txt" 2>&1
for f in /sys/fs/pstore/*; do
  [ -f "$f" ] && cp -f "$f" "$D/pstore/" 2>/dev/null
done
[ -e /proc/last_kmsg ] && cp -f /proc/last_kmsg "$D/pstore/last_kmsg" 2>/dev/null

log "dmesg (текущая загрузка)"
dmesg > "$D/dmesg.txt" 2>&1

log "logcat crash + all"
for b in crash all; do
  logcat -b "$b" -d > "$D/logcat_$b.txt" 2>&1
done

log "dropbox (system_server/watchdog/crash)"
mkdir -p "$D/dropbox"
ls -lt /data/system/dropbox/ > "$D/dropbox/_listing.txt" 2>&1
for f in /data/system/dropbox/*; do
  [ -f "$f" ] || continue
  case "$f" in
    *system_server*|*crash*|*watchdog*|*tombstone*|*anr*|*strict_mode*)
      cp -f "$f" "$D/dropbox/" 2>/dev/null
      ;;
  esac
done

log "ANR"
mkdir -p "$D/anr"
cp -f /data/anr/* "$D/anr/" 2>/dev/null

log "tombstones"
mkdir -p "$D/tombstones"
ls -lt /data/tombstones/ > "$D/tombstones/_listing.txt" 2>&1
cp -f /data/tombstones/tombstone_0* "$D/tombstones/" 2>/dev/null

log "summary"
{
  echo "--- sys.boot.reason: $(getprop sys.boot.reason 2>/dev/null) ---"
  echo
  echo "--- panic/oops/bug в ramoops ---"
  grep -aiE "panic|oops|BUG:|killed|soft lockup|rcu stall|hung task|watchdog" "$D"/pstore/* 2>/dev/null | head -60
  echo
  echo "--- ramoops хвост (что было перед падением) ---"
  tail -40 "$D"/pstore/console-ramoops-* 2>/dev/null
  echo
  echo "--- аварии во фреймворке (dropbox) ---"
  ls -lt "$D/dropbox/" 2>/dev/null | head -20
  echo
  echo "--- последние строки logcat crash ---"
  tail -40 "$D/logcat_crash.txt" 2>/dev/null
} > "$D/summary.txt"

rm -f "$D.tar.gz"
(cd "$OUT" && tar -czf "$TS.tar.gz" "$TS" 2>/dev/null)
if [ -f "$OUT/$TS.tar.gz" ]; then
  echo
  echo "Архив сохранён: $OUT/$TS.tar.gz"
  echo "Сначала смотри summary.txt и pstore/ внутри архива."
else
  echo
  echo "tar недоступен, файлы собраны в каталоге: $D"
fi
