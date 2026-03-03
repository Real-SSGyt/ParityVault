# ParityVault (Backup and Restore Utility)

ParityVault is a Bash backup and restore utility I built for my own
manual backups.

I originally created it to back up my Immich server before moving data
to cold storage. I wanted something simple, predictable,
integrity-focused, and fully manual --- no hidden automation, no
background services.

This project is shared as-is. I do not plan to actively maintain or
expand it.

------------------------------------------------------------------------

## ⚠️ AI Disclosure (Full Transparency)

This script was generated and refined using multiple AI systems.

I used:

-   Perplexity (with Claude Sonnet 4.5)
-   ChatGPT 5.1
-   Claude (Free version)

I generated multiple versions of the script across these systems and
manually combined the best logic, structure, and improvements into the
final version published here.

While AI systems helped generate the code, I reviewed, tested, merged,
and finalized everything myself.

I am intentionally transparent about this.

------------------------------------------------------------------------

## ✨ What It Does

-   Creates full directory backups using `tar`
-   Optionally splits large archives into fixed-size parts
-   Generates PAR2 recovery files (one recovery volume per
    archive/split)
-   Verifies integrity during restore
-   Attempts automatic repair if corruption is detected
-   Uses strict Bash safety settings:
    -   `set -euo pipefail`
    -   `umask 077`
-   Logs all output to a timestamped log file

------------------------------------------------------------------------

## 🔧 Default Behavior

-   Default PAR2 redundancy: **20%**
-   Default split size: **5G**
-   Split size `0` disables splitting entirely
-   One PAR2 index + one recovery volume per file (`-n1`)

You can override these interactively every time the script runs.

------------------------------------------------------------------------

## 📦 Requirements

You need:

-   `tar`
-   `split`
-   `par2` or `par2cmdline`
-   `du`
-   `numfmt`
-   `realpath`

On Debian/Ubuntu:

``` bash
sudo apt install par2 coreutils
```

------------------------------------------------------------------------

## 🚀 How To Use

Make it executable:

``` bash
chmod +x ParityVault.sh
```

Run it:

``` bash
./ParityVault.sh
```

You'll be prompted to choose:

    1) Create Backup
    2) Restore Backup

------------------------------------------------------------------------

# 🔹 Backup Mode

When selecting backup mode, you will be prompted for:

### 1️⃣ Source Path

The directory or file you want to back up.

### 2️⃣ Output Directory

Where the backup will be stored.

### 3️⃣ Backup Name

Default:

    backup_YYYYMMDD_HHMMSS

### 4️⃣ Split Size

Default:

    5G

Examples:
- `10G`
- `2G`
- `500M`
-  `0` → disables splitting

### 5️⃣ PAR2 Redundancy Percentage

Default:

    20

You can increase this (e.g., 30 or 40) for more redundancy at the cost
of storage.

------------------------------------------------------------------------

## 📂 Backup Output

### Without Splitting

    backup_name.tar
    backup_name.tar.par2
    backup_name.tar.vol*.par2

### With Splitting

    backup_name.tar.part00
    backup_name.tar.part01
    backup_name.tar.part00.par2
    backup_name.tar.part01.par2
    ...

Each split file gets its own PAR2 recovery set.

------------------------------------------------------------------------

# 🔹 Restore Mode

When restoring:

1.  Select a `.tar` or `.tar.partXX` file
2.  Select a destination directory

The script:

-   Detects whether it's split or single
-   Verifies files using PAR2
-   Attempts repair if verification fails
-   Reassembles split archives (if necessary)
-   Extracts safely

------------------------------------------------------------------------

## 🧠 What You Can Change During Execution

Each run allows you to control:

-   Source directory
-   Output directory
-   Backup name
-   Split size
-   PAR2 redundancy percentage
-   Restore destination

Everything else is automated.

------------------------------------------------------------------------

## 🔐 Integrity Model

ParityVault uses PAR2 verification before extraction.

If corruption is detected: - It attempts automatic repair - If repair
fails, restore stops safely

------------------------------------------------------------------------

## 📜 Logging

Each run generates a log file:

    parityvault_v1.0.0_YYYYMMDD_HHMMSS.log

All output is recorded.

------------------------------------------------------------------------

## 🎯 Intended Use

I built this for:

-   Manual backups
-   NAS exports
-   External drive backups
-   Cold storage
-   Personal archive protection

It is not a replacement for enterprise backup software.

------------------------------------------------------------------------

## ⚠️ Disclaimer

This is a personal utility I built for myself and decided to share
publicly.

There is:

-   No warranty
-   No guarantee
-   No active maintenance planned

Always test your backups and restore process before relying on them.

------------------------------------------------------------------------

