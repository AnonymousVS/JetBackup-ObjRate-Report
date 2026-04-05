# JetBackup-ObjRate-Report

Estimate S3 object upload rate per cPanel account from JetBackup 5 queue logs — no S3 API calls, no cron, no extra tools required.

## Quick Run (no install needed)

```bash
# All logs
bash <(curl -fsSL https://raw.githubusercontent.com/AnonymousVS/JetBackup-ObjRate-Report/main/jetbackup-obj-report.sh)

# Yesterday only
bash <(curl -fsSL https://raw.githubusercontent.com/AnonymousVS/JetBackup-ObjRate-Report/main/jetbackup-obj-report.sh) yesterday

# Today only
bash <(curl -fsSL https://raw.githubusercontent.com/AnonymousVS/JetBackup-ObjRate-Report/main/jetbackup-obj-report.sh) today

# Specific date
bash <(curl -fsSL https://raw.githubusercontent.com/AnonymousVS/JetBackup-ObjRate-Report/main/jetbackup-obj-report.sh) 2026-04-04
```

## Installation (optional)

Install once, then run anytime with just `jetbackup-obj-report.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/AnonymousVS/JetBackup-ObjRate-Report/main/jetbackup-obj-report.sh \
    -o /usr/local/sbin/jetbackup-obj-report.sh && chmod +x /usr/local/sbin/jetbackup-obj-report.sh
```

After installing:

```bash
jetbackup-obj-report.sh
jetbackup-obj-report.sh yesterday
jetbackup-obj-report.sh 2026-04-04
```

## Why?

When running JetBackup 5 with S3-compatible destinations (OVH, AWS, Wasabi, etc.) on large-scale WordPress hosting (thousands of sites), there's no built-in way to see how fast objects are being uploaded to S3.

Common approaches like `s3 ls` or S3 exporters are **impractical with millions of objects** (30M+ objects = hours of ListObjects API calls). This script takes a different approach — it reads JetBackup's own queue logs to calculate duration per account, then estimates object rate using a known baseline from live testing.

## How It Works

```
JetBackup queue log → parse Start/End time per account → Duration × baseline obj/s = Est. Objects
```

- **Data source**: `/usr/local/jetapps/var/log/jetbackup5/queue/*.log`
- **Zero S3 API calls** — reads local log files only
- **Zero resource usage** — just `grep` + `date`
- **Instant results** — no waiting for ListObjects
- **Date column** — sort by date (newest first), then by account name A-Z

## Sample Output

```
╔══════════════════════════════════════════════════════════════════════════╗
║  BACKUP REPORT — ns5041423 — 06 Apr 2026 08:30
╠══════════════════════════════════════════════════════════════════════════╣
║  Filter: All logs
╚══════════════════════════════════════════════════════════════════════════╝

 Date         │ Account            │ Start │ End   │ Duration │  Est.Objects
──────────────┼────────────────────┼───────┼───────┼──────────┼──────────────
 2026-04-05   │ jan2026newkey      │ 22:53 │ 07:34 │    8h41m │   43,806,000
 2026-04-05   │ y2026m02sv01       │ 22:45 │ 02:04 │    3h18m │   16,714,600
 2026-04-05   │ y2026m03sv01       │ 22:56 │ 10:43 │   11h47m │   59,424,400
 2026-04-05   │ y2026m04ns504      │ 22:32 │ 22:40 │    0h07m │      667,800
 2026-04-04   │ jan2026newkey      │ 02:04 │ 17:41 │   15h37m │   78,775,200
 2026-04-04   │ y2026m03sv01       │ 19:04 │ 20:52 │    1h48m │    9,076,200
──────────────┼────────────────────┼───────┼───────┼──────────┼──────────────
              │ TOTAL (6)          │       │       │   41h18m │  208,464,200

 Base rate: 1400 obj/s (from live test)
 Source: JetBackup queue logs
```

## Requirements

- JetBackup 5 on cPanel/WHM
- S3-compatible destination configured (OVH, AWS, Wasabi, etc.)
- Bash (any version)
- Root access

## Configuration

The script uses a baseline `OBJ_PER_SEC` value obtained from live testing. Default is `1400`.

### How to find your baseline

Run this **while JetBackup is actively running**:

```bash
# Requires s5cmd + S3 credentials configured
ENDPOINT="https://s3.sgp.io.cloud.ovh.net"
BUCKET="s3://your-bucket"

prev=$(s5cmd --endpoint-url "$ENDPOINT" ls "${BUCKET}/*" 2>/dev/null | wc -l)
sleep 60
curr=$(s5cmd --endpoint-url "$ENDPOINT" ls "${BUCKET}/*" 2>/dev/null | wc -l)
echo "obj/sec: $(( (curr - prev) / 60 ))"
```

### Update baseline in script

```bash
sed -i 's/OBJ_PER_SEC=1400/OBJ_PER_SEC=YOUR_VALUE/' /usr/local/sbin/jetbackup-obj-report.sh
```

## Limitations

- **obj/sec is estimated**, not measured in real-time — based on `Duration × baseline rate`
- For **real obj/sec per account**, you need live monitoring during backup execution
- Designed for JetBackup 5 with S3-compatible Incremental backup mode

## Tested Environment

| Component | Version |
|-----------|---------|
| OS | AlmaLinux 9 |
| Panel | cPanel/WHM |
| Web Server | LiteSpeed Enterprise |
| Backup | JetBackup 5 |
| S3 Destination | OVH Object Storage (Singapore) |
| Server | OVH Dedicated (AMD EPYC 4345P 8-core, 128GB RAM) |
| Scale | ~6,000 websites, 5 cPanel accounts, ~30M S3 objects |

## JetBackup Performance Settings Reference

| Setting | Value |
|---------|-------|
| Maximum Concurrent Threads | 4000 |
| Threads per fork | 500 |
| Concurrent Backup Tasks | 6 |
| Measured obj/s per account | ~1,400 |
| Backup Mode | Incremental |
| S3 Storage Class | Standard (1-hour minimum billing) |

## Related

- [Website-Daily-Create](https://github.com/AnonymousVS/Website-Daily-Create) — Bulk WordPress site creation pipeline
- [WP-Toolkit-CleanUP](https://github.com/AnonymousVS/WP-Toolkit-CleanUP) — WordPress cleanup automation
- [QuicCloud-Link-Checker](https://github.com/AnonymousVS/QuicCloud-Link-Checker) — QUIC.cloud linking automation

## License

MIT
