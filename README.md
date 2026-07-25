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
3. `ADMIN_TG_IDS` — siapa yang boleh ubah setting server dari chat bot; opsional, Enter = mati
4. `META_AD_ACCOUNT` / `META_PAGE_ID` / `META_TOKEN` — opsional, Enter = skip
5. Port dashboard (Enter = 8737)

Selesai install: buka desktop VPS di `http://IP:6080/vnc.html` (password dicetak) → login Shopee affiliate + 1 klik install userscript. Semua jalan 24/7.

## Manajemen

Satu command di server:

```bash
metapee
```

Menu: status, update, restart, set token/ID/Meta, port, log, password VNC.
Update: `metapee update` — data & konfigurasi aman.

### Dari Telegram (tanpa SSH)

Aktifkan sekali di server: `metapee admins <id-telegram-mu>`. Setelah itu di chat bot tersedia `/status` `/logs` `/token` `/ids` `/meta` `/port` `/update` `/restart` (`/help` untuk daftar lengkap). Kosong = fitur mati.

Catatan keamanan: siapa pun di `ADMIN_TG_IDS` praktis punya kendali penuh atas server — isi id-mu sendiri saja. Token yang diketik di chat sempat tersimpan di server Telegram; bot menghapus pesannya otomatis, tapi untuk kredensial paling sensitif tetap pakai terminal. Daftar admin dan `metapee reset` sengaja tidak bisa diubah dari chat.

## Catatan

- Dashboard terbuka tanpa login di `http://IP:PORT` — jangan share IP.
- Buka port dashboard + 6080 di firewall/security group cloud provider.
- Rilis di repo ini dibangun dari repo source private.
