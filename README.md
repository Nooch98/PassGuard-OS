# PassGuard OS

![badge](https://img.shields.io/badge/PassGuardOS%20-v1.0-00FBFF?style=for-the-badge&logo=security&logoColor=white)

**A password manager with advanced encryption, steganography, and panic protocols**

![badge](https://img.shields.io/badge/Flutter-3.38+-02569B?style=flat&logo=flutter)
![badge](https://img.shields.io/badge/License-MIT-green.svg?style=flat)
![badge](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20Android-lightgrey?style=flat)
![badge](https://img.shields.io/badge/Encryption-AES--256--GCM%20%7C%20PBKDF2-red?style=flat&logo=lock)
![badge](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Nooch98/PassGuard-OS)

## 📑 Table of Contents

- [What is PassGuard OS?](#what-is-passguard-os)
    - [Why PassGuard OS?](#why-passguard-os)
- [Features](#features)
    - [Security Features](#security-features)
    - [Password Management](#password-management)
    - [Chrome/Firefox Extension (OPTIONAL)](#chromefirefox-extension-optional)
    - [Backup & Sync](#backup--sync)
    - [Additional Features](#additional-features)
- [Usage](#usage)
    - [First Launch](#first-launch)
    - [Adding a Password](#adding-a-password)
    - [Enabling 2FA](#enabling-2fa)
    - [Device-to-Device Sync (QR)](#device-to-device-sync-qr)
    - [Cold Storage Backup (Steganography)](#cold-storage-backup-steganography)
- [Security](#security)
    - [Encryption Architecture](#encryption-architecture)
    - [Cryptography Details](#cryptography-details)
    - [What PassGuard OS Store & How](#what-passguard-os-store--how)
    - [Security Audit](#security-audit)
    - [Threat Model](#threat-model)
    - [Best Practices](#best-practices)
- [Priority Areas for v1.x](#priority-areas-for-v1x)
- [Disclaimer](#disclaimer)
- [FAQ](#faq)

## What is PassGuard OS?

PassGuard OS is a cross-Platform, offline password manager designed for users who take their digital security seriously. Unlike cloud-based solutions, your data never leaves your devices unless you explicitly export it.

### Why PassGuard OS?

* **✅ Offline-First** - Core vault operations run locally without cloud dependency.
* **✅ Encryption** - AES-256-GCM + PBKDF2-HMAC-SHA256 (200k iterations)
* **✅ Zero Knowledge Architecture** - Master password is never stored in plaintext, Only a PBKDF2 verification hash is stored locally. Biometric unlock stores an encrypted vault key in the OS secure keystore.
* **✅ Browser Integration** - Optional browser extension via secure local bridge
* **✅ Panic Protocol** - Emergency data wipe with biometric trigger
* **✅ Cross-Platform** - Windows, linux, Android
* **✅ Open Source** - Audit the code yourself
* **✅ No Subscriptions** - Free

## Features

### Security Features
| Feature | Description |
|--- |---
| PBKDF2 Key Derivation | 200,000 iterations with random salt per encrypted value |
| AES-256 Encryption | AES-256-GCM encryption for all stored data |
| Biometric Lock | Fingerprint(recomended)/Face ID support (Android) |
| Auto-Lock | Configurable session timeout (1-30 min) |
| Panic Mode | Emergency wipe triggered by password or biometric |
| Screenshot Protection | Prevents screenshots on Android |
| Failed Login Lockout | 5 Attempts = 30-second lockout |

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
 
### Chrome/Firefox Extension (OPTIONAL)
Optional browser extension via secure local bridge. The extension for **Firefox is officially signed by Mozilla**, ensuring security and seamless installation.

The browser extension allows:
* Autofill login credentials
* Manual password copy
* Lock vault from browser
* It only provides the credentials for that domain.
* Use shortcuts to autofill:
    - Default: `CTRL + SHIFT + L`
    - MacOS: `COMMAND + SHIFT + L`

The extension **never accesses the vault directly**.

<img width="1221" height="699" alt="Extension_Diagram" src="https://github.com/user-attachments/assets/6a431cef-6783-4db6-9712-12c07bdfebd8" />

Security design:

* The extension cannot read the vault directly.
* All credential requests are validated by the PassGuard OS application.
* Communication occurs only through `localhost` IPC.
* A **bridge authentication token** prevents unauthorized processes from accessing the vault.

https://github.com/user-attachments/assets/7a037229-5e2b-4558-850f-30d6a9c2ad13

The file `com.passguard.os.json` is located in the extension directory.

**com.passguard.os.json for Chrome/Brave/Edge/Opera GX**
```json
{
  "name": "com.passguard.os",
  "description": "PassGuard OS Native Messaging Host",
  "path": "<YOUR PATH TO passguardnativehost.exe>",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://<ID-EXTENSION>/"
  ]
}
```
**com.passguard.os.json for Firefox**

If you use the package already signed by Mozilla (recommended), do not modify `allowed_extensions`, only modify the path field.
```json
{
  "name": "com.passguard.os",
  "description": "PassGuard OS Native Messaging Host",
  "path": "<path to native host binary passguardnativehost.exe>",
  "type": "stdio",
  "allowed_extensions": [
    "passguard-os@passguard.com"
  ]
}
```

This manifest must be registered in the system so Chrome can locate the native host.
On Windows the registry key is typically:
```powershell
HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\com.passguard.os
```
pointing to the path of `com.passguard.os.json`.

You can also use the `Register_Extension_windows.ps1` script for Windows by providing the path to the `com.passguard.os.json` file when prompted, and it will be added automatically.

### PassGuard NativeHost
You need to extract `passguard_native_host`dir from the PassGuard-OS directory.
If you want to use the Chrome extension, you will need to create the executable with the following command:
```bash
mkdir build
dart compile exe bin/passguard_main.dart -o build/PassGuardNativeHost.exe
```

**Security Note**
The browser extension is designed to minimize exposure of sensitive data:

* The extension never stores credentials
* The vault remains encrypted on disk
* Decryption occurs only during an active session
* Secrets are returned only when requested for the active domain

### Bridge Authentication

The local IPC bridge requires a random authentication token generated by the PassGuard OS application.

• The token is created on first launch  
• Stored locally in the user configuration directory  
• Required for every extension request  

This prevents other local processes from impersonating the browser extension and accessing vault data.

### Linux Native Messaging Setup
For Linux users, the Native Messaging setup requires registering the binary path.

1. **Compile the Native Host**
Navigate to your native host directoy and compile the binary:
```bash
dart compile exe bin/passguard_main.dart -o PassGuardNativeHost
chmod +x PassGuardNativeHost
```

2. **Automatic Registration Script**
I provide a bash script(`Register_Extension_Linux.sh`) to handle registration automatically across all major linux browsers:
    1. Download `Register_Extension_Linux.sh`.
    2. Make it executable: `chmod +x Register_Extension_Linux.sh.
    3. Run it
    4. Follow the prompts and select your browser.  

### Backup & Sync
| Method | Capacity | Best For |
|--- |--- |---
| QR Code Sync | Low | Quick device-to-device transfer |
| Steganography | unlimited | Large vaults, covert backups |

**Steganography Feature:** Hide your entire encrypted vault inside an innocent-looking image. Perfect for cloud backup without exposing your data

### Additional Features

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
PBKDF2-HMAC-SHA256 (200,000 iterations + random salt)
     ↓
256-bit Encryption Key
     ↓
AES-256-GCM Encryption
     ↓
Encrypted SQLite Fields
```
> [!WARNING]
> PassGuard OS encrypts sensitive fields individually instead of encrypting the entire SQLite database file.
> This design allows selective decryption and improves performance while ensuring that all sensitive data remains cryptographically protected.

### Cryptography Details

• Key Derivation: PBKDF2-HMAC-SHA256  
• Iterations: 200,000  
• Salt: 16 bytes random per encrypted value  
• Encryption: AES-256-GCM  
• Nonce: 12 bytes random per encryption  
• Authentication: Built into GCM mode  
• Random generator: Dart Random.secure() (CSPRNG)  

### What PassGuard OS Store & How

| Data Type | Storage | Encryption Status |
|--- |--- |---
| Master Password | NEVER STORED | Only PBKDF2 hash |
| Account Passwords | SQLite | AES-256-GCM encrypted |
| Notes | SQLite | AES-256-GCM encrypted |
| 2FA Seeds (TOTP) | SQLite | AES-256-GCM encrypted |
| Recovery Codes | SQLite | AES-256-GCM encrypted |
| Biometric Key | OS Keystore | Platform-managed |

### Security Audit
Before releasing this as v1.0, the following measures were taken:

* Zero hardcoded passwords or keys
* No data leakage to logs
* Secure random number generation
* Memory cleanup on lock
* No vault data or secret material is transmitted to external servers.
* Open source for community audit

>[!IMPORTANT]
> While this app implements strong security practices, it has not been professionally audited. Use at your own discretion.

### Threat Model
PassGuard OS protects against:

* Physical device theft (encrypted + auto-lock)
* Reduces exposure window through session timeout and memory cleanup
* Coercion (panic mode)
* Cloud breaches (offline-only)

PassGuard OS does NOT protect against:

* Keyloggers on compromised systems
* Screen recording malware
* Full device compromise
* Physical coercion if unlocked
* Memory forensic attacks while unlocked
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
    <br>
    PassGuard OS is an <i>offline-first</i> application. Your sensitive vault data never leaves your device unless you explicitly export it. 
    <ul>
        <li><b>Privacy Note:</b> The app occasionally fetches website icons (favicons) from external APIs to improve UI. No credential or vault data is involved in these requests.</li>
        <li><b>Extension Bridge:</b> The optional browser extension communicates with the app locally via <i>Native Messaging</i> over <i>localhost</i>.</li>
        <li><b>Vault Security:</b> Crucially, <b>the browser extension never has direct access to your vault</b>. All credential requests are handled exclusively by the PassGuard OS desktop application, which manages the decrypted vault in memory and provides only the requested data for the active domain.</li>
    </ul>
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
