#!/bin/sh
# =============================================
#  AutoPIF - Pixel Canary pif.prop generator untuk Termux non-root
#  Dibuat dari autopif.sh (KOWX712) & autopif4.sh (osm0sis)
#  Dijalankan: bash autopif.sh [--product PRODUCT] [-o OUTPUT]
# =============================================

# Warna ANSI
R='\033[1;31m'   # Merah tebal  → error / peringatan
G='\033[1;32m'   # Hijau tebal  → sukses / selesai
Y='\033[1;33m'   # Kuning tebal → info / langkah
C='\033[1;36m'   # Cyan tebal   → judul / header
W='\033[1;37m'   # Putih tebal  → teks biasa
D='\033[2;37m'   # Abu-abu dim  → separator / detail
N='\033[0m'      # Reset

# Setup download function (persis dari common_func.sh)
download() { busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2" 2>/dev/null || return 1; }
if command -v curl > /dev/null 2>&1; then
    download() { curl --connect-timeout 10 -Ls "$1" > "$2" || return 1; }
fi

download_fail() {
    printf "${R}[!] Gagal download: %s${N}\n" "$1"
    rm -rf "$TMPDIR"
    exit 1
}

# Helper: tanya y/n
ask() {
    printf "${Y}%s [y/N]:${N} " "$1"
    read -r _ans
    case "$_ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# Argumen
OUTPUT="pif.prop"
PRODUCT=""
LIST_MODE=0
EXISTING=""
AUTO_SPOOF=0      # 0 = tanya dulu, 1 = langsung pakai default recommended

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            printf "${C}Penggunaan:${N} bash autopif.sh [opsi]\n"
            printf "  ${Y}--product PRODUCT${N}   Pilih device langsung (contoh: rango_beta)\n"
            printf "  ${Y}-o, --output FILE${N}   Path output (default: pif.prop)\n"
            printf "  ${Y}--existing FILE${N}     Baca spoof settings dari pif.prop lama\n"
            printf "  ${Y}--auto${N}              Langsung pakai spoof settings recommended, skip tanya\n"
            printf "  ${Y}--list${N}              Tampilkan daftar device (JSON)\n"
            exit 0 ;;
        -o|--output)   OUTPUT="$2";   shift 2 ;;
        --product)     PRODUCT="$2";  shift 2 ;;
        --list|-l)     LIST_MODE=1;   shift ;;
        --existing)    EXISTING="$2"; shift 2 ;;
        --auto)        AUTO_SPOOF=1;  shift ;;
        *) shift ;;
    esac
done

# Lokasi simpan di storage HP
# Prioritas: /sdcard/Download → /storage/emulated/0/Download → sesuai OUTPUT
SDCARD_PATH=""
for _p in "/sdcard/Download" "/storage/emulated/0/Download" "/sdcard"; do
    if [ -d "$_p" ] && [ -w "$_p" ]; then
        SDCARD_PATH="$_p"
        break
    fi
done

# Banner
printf "\n"
printf "${C}========================================\n"
printf "  AutoPIF - PlayIntegrityFix (Bash / Termux)\n"
printf "  port dari autopif.sh / autopif4.sh\n"
printf "========================================${N}\n\n"

# STEP 1: Crawl daftar device
printf "${Y}[*] Crawling Android Developer untuk daftar Pixel Beta...${N}\n"

TMPDIR="${TMPDIR:-/tmp}/autopif_$$"
mkdir -p "$TMPDIR"

download "https://developer.android.com/about/versions" "$TMPDIR/PIXEL_VERSIONS_HTML" \
    || download_fail "https://developer.android.com/about/versions"

# Persis seperti autopif.sh KOWX712
LATEST_URL=$(grep -o 'https://developer\.android\.com/about/versions/.*[0-9]"' \
    "$TMPDIR/PIXEL_VERSIONS_HTML" | sort -ru | cut -d\" -f1 | head -n1)

[ -z "$LATEST_URL" ] && download_fail "Tidak bisa parse URL versi terbaru"
printf "${Y}[*] Versi terbaru:${N} %s\n" "$LATEST_URL"

download "$LATEST_URL" "$TMPDIR/PIXEL_LATEST_HTML" || download_fail "$LATEST_URL"

# Persis seperti autopif.sh KOWX712
FI_PATH=$(grep -o 'href=".*download.*"' "$TMPDIR/PIXEL_LATEST_HTML" \
    | grep 'qpr' | cut -d\" -f2 | head -n1)
[ -z "$FI_PATH" ] && FI_PATH=$(grep -o 'href=".*download.*"' "$TMPDIR/PIXEL_LATEST_HTML" \
    | cut -d\" -f2 | head -n1)
[ -z "$FI_PATH" ] && download_fail "Tidak bisa menemukan link halaman download"

FI_URL="https://developer.android.com${FI_PATH}"
printf "${Y}[*] Halaman download:${N} %s\n" "$FI_URL"

download "$FI_URL" "$TMPDIR/PIXEL_FI_HTML" || download_fail "$FI_URL"

# Persis seperti autopif.sh KOWX712
MODEL_LIST="$(grep -A1 'tr id=' "$TMPDIR/PIXEL_FI_HTML" | grep 'td' \
    | sed 's;.*<td>\(.*\)</td>.*;\1;')"
PRODUCT_LIST="$(grep 'tr id=' "$TMPDIR/PIXEL_FI_HTML" \
    | sed 's;.*<tr id="\(.*\)">.*;\1_beta;')"

MODEL_COUNT=$(echo "$MODEL_LIST" | grep -c .)
[ "$MODEL_COUNT" -eq 0 ] && download_fail "Daftar device kosong"

# Mode --list
if [ "$LIST_MODE" -eq 1 ]; then
    printf '{"model":['
    count=0; total=$(echo "$MODEL_LIST" | wc -l)
    echo "$MODEL_LIST" | while IFS= read -r model; do
        count=$((count+1)); printf '"%s"' "$model"
        [ "$count" -lt "$total" ] && printf ','
    done
    printf '],"product":['
    count=0; total=$(echo "$PRODUCT_LIST" | wc -l)
    echo "$PRODUCT_LIST" | while IFS= read -r product; do
        count=$((count+1)); printf '"%s"' "$product"
        [ "$count" -lt "$total" ] && printf ','
    done
    printf ']}\n'
    rm -rf "$TMPDIR"; exit 0
fi

# STEP 2: Pilih device
printf "\n${C}========================================\n"
printf "  DAFTAR PIXEL DEVICE (CANARY/BETA)\n"
printf "========================================${N}\n"
i=1
while IFS= read -r model; do
    product=$(echo "$PRODUCT_LIST" | sed -n "${i}p")
    printf "  ${W}[%2d]${N} %-26s ${D}(%s)${N}\n" "$i" "$model" "$product"
    i=$((i+1))
done << MODELEOF
$MODEL_LIST
MODELEOF
printf "  ${R}[ 0]${N} Keluar\n"
printf "${C}========================================${N}\n"

if [ -n "$PRODUCT" ]; then
    case "$PRODUCT" in *_beta) ;; *) PRODUCT="${PRODUCT}_beta" ;; esac
    SEL_IDX=""
    i=1
    while IFS= read -r p; do
        [ "$p" = "$PRODUCT" ] && SEL_IDX=$i && break
        i=$((i+1))
    done << PRODEOF
$PRODUCT_LIST
PRODEOF
    [ -z "$SEL_IDX" ] && printf "${R}[!] Product '%s' tidak ditemukan.${N}\n" "$PRODUCT" && rm -rf "$TMPDIR" && exit 1
else
    printf "\n${Y}Pilih nomor device [1-%d]:${N} " "$MODEL_COUNT"
    read -r SEL_IDX
    [ "$SEL_IDX" = "0" ] && rm -rf "$TMPDIR" && exit 0
fi

SEL_MODEL=$(echo "$MODEL_LIST"    | sed -n "${SEL_IDX}p")
SEL_PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "${SEL_IDX}p")
SEL_DEVICE="${SEL_PRODUCT%_beta}"

printf "\n${G}[*] Device terpilih:${N} %s ${D}(%s)${N}\n\n" "$SEL_MODEL" "$SEL_PRODUCT"

# STEP 3: Flash Station
printf "${Y}[*] Crawling Android Flash Tool untuk build canary...${N}\n"

download "https://flash.android.com" "$TMPDIR/PIXEL_FLASH_HTML" \
    || download_fail "https://flash.android.com"

FLASH_KEY=$(grep -o '<body data-client-config=.*' "$TMPDIR/PIXEL_FLASH_HTML" \
    | cut -d\; -f2 | cut -d\& -f1)
printf "${Y}[*] Flash key:${N} %s...\n" "${FLASH_KEY:0:20}"

STATION_URL="https://content-flashstation-pa.googleapis.com/v1/builds?product=${SEL_PRODUCT}&key=${FLASH_KEY}"

if command -v curl > /dev/null 2>&1; then
    curl --connect-timeout 10 -H "Referer: https://flash.android.com" \
         -s "$STATION_URL" > "$TMPDIR/PIXEL_STATION_JSON" \
    || download_fail "Flash Station"
else
    busybox wget -T 10 --header "Referer: https://flash.android.com" \
         -qO - "$STATION_URL" > "$TMPDIR/PIXEL_STATION_JSON" \
    || download_fail "Flash Station"
fi

# Parse canary JSON - persis seperti autopif4.sh osm0sis
if command -v tac > /dev/null 2>&1; then
    tac "$TMPDIR/PIXEL_STATION_JSON" \
        | grep -m1 -A13 '"canary": true' > "$TMPDIR/PIXEL_CANARY_JSON"
else
    awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--) print lines[i]}' \
        "$TMPDIR/PIXEL_STATION_JSON" \
        | grep -m1 -A13 '"canary": true' > "$TMPDIR/PIXEL_CANARY_JSON"
fi

ID=$(grep 'releaseCandidateName' "$TMPDIR/PIXEL_CANARY_JSON" | cut -d\" -f4)
INCREMENTAL=$(grep 'buildId' "$TMPDIR/PIXEL_CANARY_JSON" | cut -d\" -f4)

if [ -z "$ID" ] || [ -z "$INCREMENTAL" ]; then
    printf "${R}[!] Failed to get pif.prop${N}\n"
    rm -rf "$TMPDIR"; exit 1
fi

printf "${Y}[*] Release ID :${N} %s\n" "$ID"
printf "${Y}[*] Incremental:${N} %s\n" "$INCREMENTAL"

# STEP 4: Security Patch
printf "${Y}[*] Crawling Pixel Update Bulletins untuk security patch...${N}\n"

download "https://source.android.com/docs/security/bulletin/pixel" \
    "$TMPDIR/PIXEL_SECBULL_HTML" || printf "${R}[!] Gagal ambil bulletin, akan estimasi${N}\n"

CANARY_ID=$(grep '"id"' "$TMPDIR/PIXEL_CANARY_JSON" \
    | sed -e 's;.*canary-\(.*\)".*;\1;' -e 's;^\(.\{4\}\);\1-;')

SECURITY_PATCH=""
if [ -n "$CANARY_ID" ] && [ -f "$TMPDIR/PIXEL_SECBULL_HTML" ]; then
    SECURITY_PATCH=$(grep "<td>$CANARY_ID" "$TMPDIR/PIXEL_SECBULL_HTML" \
        | sed 's;.*<td>\(.*\)</td>;\1;' | head -1)
fi

if [ -z "$SECURITY_PATCH" ]; then
    DATE_PART=$(echo "$ID" | grep -o '\.[0-9]\{6\}' | head -1 | tr -d '.')
    if [ -n "$DATE_PART" ]; then
        SP_YEAR="20$(echo "$DATE_PART" | cut -c1-2)"
        SP_MONTH=$(echo "$DATE_PART" | cut -c3-4)
        SP_DAY=$(echo "$DATE_PART" | cut -c5-6)
        SECURITY_PATCH="${SP_YEAR}-${SP_MONTH}-${SP_DAY}"
    else
        SECURITY_PATCH="${CANARY_ID}-05"
    fi
    printf "${R}[!] Estimasi security patch:${N} %s\n" "$SECURITY_PATCH"
fi
printf "${Y}[*] Security Patch:${N} %s\n" "$SECURITY_PATCH"

# STEP 5: Spoof Settings
# Default recommended (format baru: nilai 1/0)
spoofBuild=1
spoofProps=1
spoofProvider=1
spoofSignature=0
spoofVendingFinger=1
spoofVendingSdk=0

# Cek apakah ada pif.prop lama untuk di-preserve
PIFPROP_EXISTING="${EXISTING:-}"
[ -z "$PIFPROP_EXISTING" ] && [ -f "/data/adb/pif.prop" ] \
    && PIFPROP_EXISTING="/data/adb/pif.prop"
[ -z "$PIFPROP_EXISTING" ] && [ -f "/data/adb/modules/playintegrityfix/pif.prop" ] \
    && PIFPROP_EXISTING="/data/adb/modules/playintegrityfix/pif.prop"

if [ -f "$PIFPROP_EXISTING" ]; then
    printf "${Y}[*] Membaca spoof settings dari:${N} %s\n" "$PIFPROP_EXISTING"
    for config in spoofBuild spoofProps spoofProvider spoofSignature spoofVendingFinger spoofVendingSdk; do
        _val=$(grep "^${config}=" "$PIFPROP_EXISTING" 2>/dev/null | cut -d= -f2 | head -1)
        [ -n "$_val" ] && eval "$config=$_val"
    done
fi

# Tampilkan spoof settings dan tawarkan edit
printf "\n${C}========================================\n"
printf "  SPOOF SETTINGS  (1=aktif, 0=nonaktif)\n"
printf "========================================${N}\n"

_spoof_color() {
    [ "$1" = "1" ] && printf "${G}%s${N}" "$1" || printf "${D}%s${N}" "$1"
}

printf "  ${W}[1]${N} spoofBuild        = "; _spoof_color "$spoofBuild"; printf "\n"
printf "  ${W}[2]${N} spoofProps        = "; _spoof_color "$spoofProps"; printf "\n"
printf "  ${W}[3]${N} spoofProvider     = "; _spoof_color "$spoofProvider"; printf "\n"
printf "  ${W}[4]${N} spoofSignature    = "; _spoof_color "$spoofSignature"; printf "\n"
printf "  ${W}[5]${N} spoofVendingFinger= "; _spoof_color "$spoofVendingFinger"; printf "\n"
printf "  ${W}[6]${N} spoofVendingSdk   = "; _spoof_color "$spoofVendingSdk"; printf "\n"
printf "${C}========================================${N}\n"

if [ "$AUTO_SPOOF" -eq 0 ]; then
    printf "\n  ${Y}[e]${N} Edit spoof settings\n"
    printf "  ${W}[enter]${N} Lanjut pakai settings di atas\n"
    printf "\n${Y}Pilihan:${N} "
    read -r _spoof_choice

    if [ "$_spoof_choice" = "e" ] || [ "$_spoof_choice" = "E" ]; then
        printf "\n${Y}[*] Edit spoof settings (ketik 1/0, enter = pakai nilai saat ini)${N}\n\n"
        for config in spoofBuild spoofProps spoofProvider spoofSignature spoofVendingFinger spoofVendingSdk; do
            _cur=$(eval echo "\$$config")
            printf "  ${W}%-20s${N} [" "$config"; _spoof_color "$_cur"; printf "]: "
            read -r _new
            if [ "$_new" = "1" ] || [ "$_new" = "0" ]; then
                eval "$config=$_new"
            elif [ -n "$_new" ]; then
                printf "  ${R}[!] Input tidak valid (harus 1 atau 0), tetap pakai: %s${N}\n" "$_cur"
            fi
        done
        printf "\n${G}[*] Spoof settings setelah edit:${N}\n"
        printf "  spoofBuild=%s  spoofProps=%s  spoofProvider=%s\n" \
            "$spoofBuild" "$spoofProps" "$spoofProvider"
        printf "  spoofSignature=%s  spoofVendingFinger=%s  spoofVendingSdk=%s\n" \
            "$spoofSignature" "$spoofVendingFinger" "$spoofVendingSdk"
    fi
else
    printf "\n${Y}[*] --auto: langsung pakai settings di atas.${N}\n"
fi

# STEP 6: Build dan simpan pif.prop
FINGERPRINT="google/${SEL_PRODUCT}/${SEL_DEVICE}:CANARY/${ID}/${INCREMENTAL}:user/release-keys"

PIF_CONTENT="MANUFACTURER=Google
MODEL=$SEL_MODEL
FINGERPRINT=$FINGERPRINT
BRAND=google
PRODUCT=$SEL_PRODUCT
DEVICE=$SEL_DEVICE
RELEASE=CANARY
ID=$ID
INCREMENTAL=$INCREMENTAL
TYPE=user
TAGS=release-keys
SECURITY_PATCH=$SECURITY_PATCH
DEVICE_INITIAL_SDK_INT=32
BUILD.ID=$ID
SECURITY_PATCH=$SECURITY_PATCH
API_LEVEL=32
spoofBuild=$spoofBuild
spoofProps=$spoofProps
spoofProvider=$spoofProvider
spoofSignature=$spoofSignature
spoofVendingFinger=$spoofVendingFinger
spoofVendingSdk=$spoofVendingSdk
#
#========================================
# Generated by AutoPIF (Bash / Termux port)
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
#
# Credits:
#   Rahmat Sobrian     - AutoPIF Termux port & customization
#   KOWX712            - autopif.sh & PlayIntegrityFix [INJECT]
#   osm0sis            - autopif4.sh & PlayIntegrityFork
#   chiteroman         - PlayIntegrityFix original
#
# Sources used:
#   https://developer.android.com/about/versions
#   https://flash.android.com (Flash Station API)
#   https://source.android.com/docs/security/bulletin/pixel
#   https://github.com/KOWX712/PlayIntegrityFix
#   https://github.com/osm0sis/PlayIntegrityFork
#========================================"

printf "\n${Y}[*] Konten pif.prop:${N}\n"
printf "${D}-----------------------------------------${N}\n"
printf "%s\n" "$PIF_CONTENT"
printf "${D}-----------------------------------------${N}\n\n"

# Fungsi konversi prop → JSON
prop_to_json() {
    # $1 = isi PIF_CONTENT (string)
    # Output: JSON string dengan komentar kredit # di bawah (bukan field JSON)
    _gen_date=$(date '+%Y-%m-%d %H:%M:%S')

    printf '{\n'

    # Parse setiap baris key=value (skip baris komentar # dan kosong)
    _total=$(echo "$1" | grep -c '^[A-Za-z_]')
    _count=0
    echo "$1" | while IFS= read -r _line; do
        case "$_line" in '#'*|'') continue ;; esac
        _key=$(echo "$_line" | cut -d= -f1)
        _val=$(echo "$_line" | cut -d= -f2-)
        [ -z "$_key" ] && continue
        _count=$((_count + 1))
        if [ "$_count" -lt "$_total" ]; then
            printf '  "%s": "%s",\n' "$_key" "$_val"
        else
            printf '  "%s": "%s"\n' "$_key" "$_val"
        fi
    done

    printf '}\n'
    printf '\n'
    printf '#========================================\n'
    printf '# Generated by AutoPIF (Bash / Termux port)\n'
    printf '# Generated on: %s\n' "$_gen_date"
    printf '#\n'
    printf '# Credits:\n'
    printf '#   Rahmat Sobrian - AutoPIF Termux port & customization\n'
    printf '#   KOWX712       - autopif.sh & PlayIntegrityFix [INJECT]\n'
    printf '#   osm0sis          - autopif4.sh & PlayIntegrityFork\n'
    printf '#   chiteroman      - PlayIntegrityFix original\n'
    printf '#\n'
    printf '# Sources used:\n'
    printf '#   https://developer.android.com/about/versions\n'
    printf '#   https://flash.android.com (Flash Station API)\n'
    printf '#   https://source.android.com/docs/security/bulletin/pixel\n'
    printf '#   https://github.com/KOWX712/PlayIntegrityFix\n'
    printf '#   https://github.com/osm0sis/PlayIntegrityFork\n'
    printf '# ========================================\n'
}

# STEP 7: Pilih format output
printf "${C}========================================\n"
printf "  FORMAT OUTPUT\n"
printf "========================================${N}\n"
printf "  ${W}[1]${N} pif.prop  ${D}(format key=value)${N}\n"
printf "  ${W}[2]${N} pif.json  ${D}(format JSON)${N}\n"
printf "  ${W}[3]${N} Keduanya  ${D}(pif.prop + pif.json)${N}\n"
printf "${C}========================================${N}\n"
printf "\n${Y}Pilihan format [1/2/3]:${N} "
read -r _fmt_choice

# Tentukan format
SAVE_PROP=0; SAVE_JSON=0
case "$_fmt_choice" in
    2) SAVE_JSON=1 ;;
    3) SAVE_PROP=1; SAVE_JSON=1 ;;
    *) SAVE_PROP=1 ;;  # default: prop
esac

# Generate JSON content jika diperlukan
if [ "$SAVE_JSON" -eq 1 ]; then
    JSON_CONTENT=$(prop_to_json "$PIF_CONTENT")
fi

# STEP 8: Pilih lokasi simpan
printf "\n${C}========================================\n"
printf "  SIMPAN FILE\n"
printf "========================================${N}\n"
printf "  ${W}[1]${N} Folder Download HP  ${D}(/sdcard/Download/)${N}\n"
printf "  ${W}[2]${N} Folder saat ini     ${D}($(pwd)/)${N}\n"
printf "  ${W}[3]${N} Keduanya\n"
printf "${C}========================================${N}\n"
printf "\n${Y}Pilihan lokasi [1/2/3]:${N} "
read -r _save_choice

# Fungsi simpan file
save_to() {
    _dest="$1"
    _content="$2"
    _dir=$(dirname "$_dest")
    if [ ! -d "$_dir" ]; then
        mkdir -p "$_dir" 2>/dev/null || { printf "${R}[!] Gagal buat folder: %s${N}\n" "$_dir"; return 1; }
    fi
    printf '%s\n' "$_content" > "$_dest" \
        && printf "${G}[+] Tersimpan: %s${N}\n" "$_dest" \
        || printf "${R}[!] Gagal simpan ke: %s${N}\n" "$_dest"
}

# Tentukan lokasi berdasarkan pilihan
case "$_save_choice" in
    1) _locs="sdcard" ;;
    3) _locs="sdcard local" ;;
    *) _locs="local" ;;
esac

for _loc in $_locs; do
    if [ "$_loc" = "sdcard" ]; then
        if [ -n "$SDCARD_PATH" ]; then
            _base="$SDCARD_PATH"
        else
            printf "${R}[!] /sdcard/Download tidak tersedia, pakai folder saat ini.${N}\n"
            _base="$(pwd)"
        fi
    else
        _base="$(pwd)"
    fi

    [ "$SAVE_PROP" -eq 1 ] && save_to "$_base/pif.prop" "$PIF_CONTENT"
    [ "$SAVE_JSON" -eq 1 ] && save_to "$_base/pif.json" "$JSON_CONTENT"
done

# Cleanup
rm -rf "$TMPDIR"
printf "\n${G}[*] Done!${N}\n"