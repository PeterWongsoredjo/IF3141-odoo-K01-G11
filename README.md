# Kopi Eyang Integrated ERP

> Sistem Informasi terintegrasi berbasis **Odoo 17 Community Edition** untuk *Kopi Eyang* Bandung.

**Mata Kuliah:** IF3141 Sistem Informasi · Institut Teknologi Bandung
**Kelas:** K01 · **Kelompok:** G11

---

## Identitas Kelompok

| NIM | Nama |
|---|---|
| 13523002 | Refki Alfarizi |
| 13523003 | Dave Daniell Yanni |
| 13523012 | Felix Chandra |
| 13523036 | Yonatan Edward Njoto |
| 13523039 | Peter Wongsoredjo |

---

## Identitas Sistem

- **Nama Sistem:** Kopi Eyang Integrated ERP
- **Perusahaan:** Kopi Eyang Bandung
- **Platform:** Odoo 17 Community Edition (Docker)
- **Modul Kustom:** `simple_erp`

---

## Deskripsi Sistem

Kopi Eyang sebelumnya menjalankan operasionalnya secara manual: pencatatan penjualan dilakukan di POS, stok bahan baku hanya berdasarkan visual, dan rekap keuangan disusun ulang melalui spreadsheet terpisah. Pendekatan ini menimbulkan banyak titik *friction*: data tidak konsisten, kontrol stok lambat sehingga sering terjadi *stock-out*, dan analisis keuangan baru bisa dilakukan setelah seluruh berkas direkonsiliasi manual. **Kopi Eyang Integrated ERP** hadir sebagai transisi dari sistem manual tersebut menuju ekosistem digital terpadu di atas **Odoo 17**, yang menyatukan inventaris, transaksi penjualan, manajemen vendor, kehadiran karyawan, dan pelaporan keuangan dalam satu platform yang konsisten dan dapat diaudit.

Fitur utama sistem ini mencakup **Custom Dashboard berbasis OWL (Odoo Web Library)** yang menampilkan KPI eksekutif (pendapatan, pengeluaran, *net profit*, *stock movement*) dengan filter granularitas *daily/weekly/monthly/yearly* untuk tiap grafik; **RBAC 5-Tier** yang membagi hak akses ke dalam peran **Admin, Founder, Kasir, Barista, dan Kitchen** sehingga setiap karyawan hanya melihat data yang relevan dengan tanggung jawabnya; **manajemen stok bahan baku (*raw material*)** dengan *low-stock alert* otomatis, riwayat perubahan stok yang wajib disertai catatan (audit-trail), dan integrasi langsung dengan modul *Invoice Upload* untuk pencatatan pembelian dari vendor; serta **integrasi data POS** melalui *Sales CSV Reader* yang secara otomatis memotong stok produk jadi setiap kali transaksi penjualan masuk. Seluruh data ini saling terhubung — penjualan memengaruhi stok produk, pembelian memengaruhi stok bahan baku dan pengeluaran, dan semuanya teragregasi *real-time* ke dashboard eksekutif.

---

## Cara Menjalankan Sistem

### Prasyarat

- **Docker Desktop** — [Download](https://www.docker.com/products/docker-desktop/)
- **Python 3.11** (opsional, untuk linting / IDE tooling)

### Langkah-langkah

#### 1. Jalankan service Odoo + PostgreSQL

```bash
docker compose up -d
```

> *Expected result:* container `odoo` dan `db` berjalan, log menunjukkan Odoo siap menerima koneksi di port `8069`.

📷 **Screenshot:** _Tempelkan screenshot terminal hasil `docker compose up -d` di sini._

---

#### 2. Akses Odoo di browser

Buka **http://localhost:8069** lalu *login* dengan kredensial default `admin` / `admin`.

📷 **Screenshot:** _Tempelkan screenshot halaman login Odoo di sini._

---

#### 3️. Aktifkan Developer Mode

**Settings → Developer Tools → Activate the developer mode** (atau tambahkan `?debug=1` ke URL).

📷 **Screenshot:** _Tempelkan screenshot menu Settings dengan Developer Mode aktif di sini._

---

#### 4️. Instalasi Modul `simple_erp`

1. Masuk ke menu **Apps**.
2. Klik **Update Apps List** (tombol muncul setelah Developer Mode aktif).
3. Hapus filter default `Apps`, lalu cari **`simple_erp`**.
4. Klik **Activate** pada modul *Kopi Eyang Simple ERP*.

> *Expected result:* modul `simple_erp` berstatus *Installed*, menu baru **Business ERP** muncul di *navbar*.

📷 **Screenshot:** _Tempelkan screenshot Apps list dengan `simple_erp` ter-install di sini._

📷 **Screenshot:** _Tempelkan screenshot menu Business ERP yang sudah muncul di sini._

---

#### 5️. (Opsional) Import Database Demo

Untuk memulai dengan data demo yang sudah dipersiapkan tim:

```bash
# Windows
.\scripts\import_db.cmd

# macOS / Linux
./scripts/import_db.sh
```

📷 **Screenshot:** _Tempelkan screenshot dashboard setelah import database di sini._

---

#### 6. Restart untuk Menerapkan Perubahan Modul

Apabila ada perubahan pada file modul (`custom_addons/simple_erp/`):

```bash
docker compose down
docker compose up -d
```

> `docker-compose.yml` sudah disetel dengan flag `-u simple_erp`, sehingga modul otomatis di-*upgrade* setiap kali container dijalankan ulang.

---

## Kredensial Role

Berikut akun *dummy* untuk masing-masing peran dalam sistem. Gunakan untuk demonstrasi RBAC 5-Tier.

| Role | Email | Password | Hak Akses Utama |
|---|---|---|---|
| **Admin** | `admin` | `admin` | Akses penuh sistem, konfigurasi, user management |
| **Founder / CEO** | `founder` | `founder` | Dashboard eksekutif, laporan keuangan, semua modul read/write, user management |
| **Kasir** | `kasir` | `kasir` | Sales CSV upload, akses *read* ke produk & stok, attendance & employee |
| **Barista** | `barista` | `barista` | Stok bahan baku (read/write), invoice upload, attendance & employee |
| **Kitchen** | `kitchen` | `kitchen` | Stok bahan baku (read/write), invoice upload, attendance & employee |

---

## Struktur Direktori

```
IF3141-odoo-K01-G11/
├── config/                   # Konfigurasi Odoo (odoo.conf)
├── custom_addons/
│   └── simple_erp/           # Modul kustom Kopi Eyang
│       ├── models/           # Data models & business logic
│       ├── views/            # Form, tree, dashboard views
│       ├── security/         # RBAC groups & access rules
│       └── static/src/       # OWL components & assets
├── dump/                     # Database dump (import/export)
├── scripts/                  # Script migrasi database
└── docker-compose.yml        # Orchestration Odoo + PostgreSQL
```

---

## Database Migration

Selalu hentikan service sebelum migrasi:

```bash
docker compose down
```

**Export** (backup database saat ini):

```bash
# Windows
.\scripts\export_db.cmd

# macOS / Linux
./scripts/export_db.sh
```

**Import** (restore dari dump rekan tim):

```bash
# Windows
.\scripts\import_db.cmd

# macOS / Linux
./scripts/import_db.sh
```

Untuk backup penuh termasuk *filestore* dan konfigurasi, gunakan `export_db_full.cmd` / `import_db_full.cmd`.

---

## Kesimpulan & Saran Pengembangan

**Kopi Eyang Integrated ERP** telah berhasil mentransformasi alur kerja Kopi Eyang dari pencatatan manual menjadi sistem terintegrasi yang efisien dan akuntabel. Dengan adanya dashboard eksekutif *real-time*, manajemen stok yang ter-audit, dan pembagian peran yang jelas melalui RBAC 5-Tier, *founder* dapat mengambil keputusan strategis berdasarkan data aktual, sementara karyawan operasional dapat menjalankan tugas hariannya tanpa perlu duplikasi pencatatan.

Beberapa arah pengembangan ke depan yang direkomendasikan:

- **Integrasi IoT** — sensor *weight scale* untuk monitoring stok bahan baku secara otomatis dan *smart fridge* untuk *cold-chain temperature logging*.
- **Modul Loyalty** — sistem *point reward* dan *tiered membership* terintegrasi dengan POS untuk meningkatkan retensi pelanggan.
- **Mobile Companion App** — aplikasi mobile khusus untuk *attendance* dan *quick stock check* bagi barista/kitchen.
- **Demand Forecasting** — modul prediktif berbasis *machine learning* untuk merekomendasikan jumlah pembelian bahan baku berdasarkan tren historis dan musiman.
- **Integrasi Payment Gateway** — koneksi langsung ke QRIS / e-wallet untuk *reconciliation* otomatis.

