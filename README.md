# Metapee — Video Ads Generator

Pipeline konten affiliate Shopee: kirim video + link lewat **Telegram** → server otomatis framing video 9:16 (hook di atas), generate link affiliate, kirim balik siap posting — plus dashboard antrian & draft iklan Meta.

## Install (1 baris)

VPS Ubuntu/Debian kosongan, amd64, RAM ≥2GB:

```bash
curl -fsSL https://raw.githubusercontent.com/onnayokheng/metapee-releases/main/install.sh | sudo bash
```

Installer akan tanya:
1. `TELEGRAM_TOKEN` — token bot kamu (bikin di @BotFather)
2. `ALLOWED_TG_IDS` — user id Telegram yang boleh pakai (cek punyamu di @userinfobot)
3. `META_AD_ACCOUNT` / `META_PAGE_ID` / `META_TOKEN` — opsional, Enter = skip
4. Port dashboard (Enter = 8737)

Selesai install: buka desktop VPS di `http://IP:6080/vnc.html` (password dicetak) → login Shopee affiliate + 1 klik install userscript. Semua jalan 24/7.

## Manajemen

Satu command di server:

```bash
metapee
```

Menu: status, update, restart, set token/ID/Meta, port, log, password VNC.
Update: `metapee update` — data & konfigurasi aman.

## Catatan

- Dashboard terbuka tanpa login di `http://IP:PORT` — jangan share IP.
- Buka port dashboard + 6080 di firewall/security group cloud provider.
- Rilis di repo ini dibangun dari repo source private.
