# Security Policy

I am the sole developer of PassGuard OS. My goal is to build a tool that prioritizes user privacy and security. Because this project is open-source and handles sensitive information, I believe in full transparency as the best way to maintain a secure environment.

## 📢 Public Disclosure Policy
I prefer transparency over secrecy. If you find a security vulnerability, **please report it directly as a GitHub Issue.** This allows the community to see the problem, help verify it, and contribute to the solution.

### How to report a security issue:
1. **Open a new Issue:** Use the `[SECURITY]` tag in the issue title.
2. **Provide details:** Include a clear description of the vulnerability and, if possible, a Proof of Concept (PoC).
3. **Protect the users:** - **Do not** include real credentials, vault data, or sensitive keys in the issue.
   - Sanitize any logs or memory dumps you share.
4. **Be constructive:** If you have an idea for a fix or a Pull Request, please share it.

## 🤝 Collaboration & Fixes
I commit to:
1. Responding publicly to your report as soon as possible.
2. Providing a clear timeline for the fix.
3. Keeping the community updated throughout the remediation process.

## 🛡️ Safe Harbor
I provide a Safe Harbor for researchers acting in good faith. I will not pursue legal action if you:
* Conduct your research on your own local instance/installation and with your own data.
* Do not attempt to distribute modified versions of PassGuard OS for malicious purposes.
* Follow the disclosure guidelines above.

## ⚠️ Known Limitations & Threat Model
PassGuard OS is designed as an offline-first tool, but it is not entirely network-isolated. Please understand the following security boundaries:

* **Network Activity:** - The core vault and encryption operations are strictly local and do not require internet access.
    - However, the UI may perform network requests to fetch website favicons to enhance user experience. These requests do not involve sensitive vault data or credentials.
    - The browser extension communicates locally with the PassGuard desktop application via Native Messaging (localhost). This IPC bridge does not communicate with any external servers.
* **Kernel-Level Risks:** If the host OS is compromised (e.g., Root/Kernel access, keyloggers, or memory forensics), the vault must be considered compromised.
* **Personal Use Only:** This software is not hardened for high-stakes enterprise or state-level surveillance environments.
* **Zero-Knowledge Architecture:** I have designed the app so that I never have access to your data. However, this also means that if you forget your master password, your data is permanently lost.

I am most interested in security research findings that fall within the scope of a personal password manager, such as vulnerabilities in the encryption flow, the IPC bridge, or the data reassembly logic.

*Thank you for helping me secure PassGuard OS through complete transparency.*
