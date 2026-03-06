# PassGuard OS

![badge](https://img.shields.io/badge/PassGuardOS%20-v1.0-00FBFF?style=for-the-badge&logo=security&logoColor=white)

**A password manager with advanced encryption, steganography, and panic protocols**

![badge](https://img.shields.io/badge/Flutter-3.38+-02569B?style=flat&logo=flutter)
![badge](https://img.shields.io/badge/License-MIT-green.svg?style=flat)
![badge](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20Android-lightgrey?style=flat)
![badge](https://img.shields.io/badge/Encryption-AES--256-red?style=flat&logo=lock)
![badge](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Nooch98/PassGuard-OS)

## What is PassGuard OS?

PassGuard OS is a cross-Platform, offline password manager designed for users who take their digital security seriusly. Unlike cloud-based solutions, your data never leaves your devices unless you explicitly export it.

### Why PassGuard OS?

* **✅ 100% Offline** - No cloud, no tracking, no telemetry
* **✅ Encryption** - AES-256 + PBKDF2 (100k iterations)
* **✅ Zero Knowledge Architecture** - Master password never stored
* **✅ Panic Protocol** - Emergency data wipe with biometric trigger
* **✅ Cross-Platform** - Windows, linux. Android
* **✅ Open Source** - Audit the code yourself
* **✅ No Subscriptions** - Free

## Features

### Security Features
| Feature | Description |
|--- |---
| PBKDF2 Key Derivation | 100.00 iterations with unique salt per user |
| AES-256 Encryption | AES-256 encryption for all stored data |
| Biometric Lock | Fingerprint(recomended)/Face ID support (Android) |
| Auto-Lock | Configurable session timeout (1-30 min) |
| Panic Mode | Emergency wipe triggered by password or biometric |
| Screenshot Protection | Prevents screenshots on Android |
| Failed Login Lockout | 5 Attemps = 30-second lockout |

### Password Management
* **Advanced Password Generator**
    * Random Passwords (8-64 characters)
    * Memorable passphrases (4-6 words)
    * PIN Codes (4-12 digits)
    * Real-time strength analysis
    * Exclude ambiguous characteres option
* **2FA/TOTP Support**
    * QR code scanning for authenticator codes
    * Real-time TOTP code generation
    * 30-second countdown timer
* **Password Health Dashboard**
    * Weak password detection
    * Reuse detection
    * Old password alerts (90+ days)
    * Overall security score (0-100)
* **Organization Tools**
    * Categories: Personal, Work, Finance, Social
    * Favorites system
    * Search & filter
    * Sort by: Name, Date, Last Used, Favorites
    * Encrypted notes per entry
    * Password history (last 5 changes)

### Backup & Sync
| Method | Capacity | Best For |
|--- |--- |---
| QR Code Sync | Low | Quick device-to-device transfer |
| Steganography | unlimited | Large vaults, covert backups |

**Steganography Feature:** Hide your entire encrypted vault inside an innocent-looking image. Perfect for cloud backup without exposing your data

### Aditional Features

* **Recovery Code Manager** - Import & track 2FA backup codes
* **Encrypted File Vault** - Store sensitive documents *(Beta - functional but may have issues)*
* **Smart Clipboard** - Auto-clear after 30 seconds
* **Dark Cyberpunk Theme** - Easy on the eyes
* **Offline-First** - Works without internet

## Usage

### First Launch

1. **First-Time Setup**:
   - Create master password (min 8 characters)
   - Confirm master password
   - Set panic password (different from master)

#### Adding a Password
```
1. Tap + button
2. Select "Add New Password"
3. Fill in details (use generator for strong passwords)
4. Choose category
5. Save
```

#### Enabling 2FA
```
1. Tap + → "Scan QR 2FA"
2. Scan QR code from your service
3. Select account to link
```

#### Device-to-Device Sync (QR)
```
Device A: Settings → Generate Transmission QR
Device B: Settings → Receive Data Stream → Scan QR
```

#### Cold Storage Backup (Steganography)
```
Hide:    Settings → Cold Storage → Inject Into Image
Restore: Settings → Cold Storage → Extract From Image
```

## Security


### Encryption Architecture
```
User Password
     ↓
PBKDF2 (100,000 iterations + unique salt)
     ↓
256-bit Encryption Key
     ↓
AES-256-CBC Encryption
     ↓
Encrypted SQLite Database
```

### What PassGuard OS Store & How

| Data Type | Storage | Encryption Status |
|--- |--- |---
| Master Password | NEVER STORED | Only PBKDF2 hash |
| Account Passwords | SQLite | AES-256 encrypted |
| Notes | SQLite | AES-256 encrypted |
| 2FA Seeds (TOTP) | SQLite | Not encrypted (already secret) |
| Recovery Codes | SQLite | AES-256 encrypted |
| Biometric Key | OS Keystore | Platform-managed |

### Security Audit
Before releasing this as v1.0, the following measures were taken:

* Zero hardcoded passwords or keys
* No data leakage to logs
* Secure random number generation
* Memory cleanup on lock
* No external network calls
* Open source for community audit

>[!IMPORTANT]
> While this app implements strong security practices, it has not been professionally audited. Use at your own discretion.

### Thread Model
PassGuard OS protects against:

* Physical device theft (encrypted + auto-lock)
* Malware reading memory (short session + cleanup)
* Coercion (panic mode)
* Cloud breaches (offline-only)

PassGuard OS does NOT protect against:

* Keyloggers on compromised systems
* Screen recording malware
* Physical coercion if unlocked
* Advanced persistent threats (APTs)

### Best Practices

1. Use a strong, unique master password (16+ chars recommended)
2. Enable biometric unlock for convenience
3. Set session timeout to 5 minutes or less
4. Backup regularly (steganography recommended)
5. Enable 2FA for all accounts that support it
6. Run security audit monthly
7. Never reuse passwords
8. Keep your OS and PassGuard OS updated


### Priority Areas for v1.x
1. **Bug fixes and stability**
2. **iOS support (I dont have any IOS device so i cant test and build)**
3. **Documentation improvements**
4. **Security audit feedback**


## Disclaimer

**PassGuard OS v1.0 - First Public Release**

This software is provided "as is" for personal use and educational purposes.

### What this means:
* Open source and auditable
* No tracking or telemetry
* Industry-standard encryption (AES-256)
* Active development and support

### Important limitations:
* Not professionally security audited
* First public release - may contain bugs
* Use at your own risk
* Not intended for enterprise/commercial use
* Always maintain backups

**No warranty is provided**

## FAQ
<details>
<summary><b>Is my data sent to the cloud?</b></summary>
    No. PassGuard OS is 100% offline. Your data never leaves your device unless you explicitly export it (QR, steganography, CSV). There are no analytics, no telemetry, no network calls.
</details>
<details>
<summary><b>What if I forget my master password?</b></summary>
    There is no recovery mechanism by design. If you forget your master password, your data is permanently locked. This is a feature, not a bug - it ensures zero-knowledge security. Always keep backups!
</details>
<details>
<summary><b>Is this safe to use?</b></summary>
    PassGuard OS uses proven encryption (AES-256, PBKDF2) and is open source. However, it's not professionally audited. For maximum safety:
    - Review the code yourself
    - Start with non-critical passwords
    - Maintain backups
    - Report any issues you find
</details>
<details>
<summary><b>How do I backup my vault?</b></summary>
    Three methods:
    1. <b>QR Sync</b>: Quick, for small vaults (~25 passwords)
    2. <b>Steganography</b>: Best for large vaults (hide in image)
    3. <b>CSV Export</b>: Universal, but less secure during transfer
</details>
<details>
<summary><b>What's the panic mode for?</b></summary>
    If under duress (border crossing, robbery), use your panic password or hidden biometric button to instantly wipe all vault data. Cannot be undone - ensure you have backups!
</details>

<div align="center">
Thank You for Trying PassGuard OS v1.0!
</div align="center">
