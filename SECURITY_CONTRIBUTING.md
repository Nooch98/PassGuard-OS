# Guidelines for Contributing to Security

Thank you for helping me maintain the security of PassGuard OS. Since it's an open-source tool designed to work offline, your contributions, whether vulnerability reports or patches, are vital.

## How to Contribute Security Fixes

### 1. Verification (Proof of Concept)
Before submitting a fix, make sure you can reproduce the issue. Since security vulnerabilities are best understood through use in real-world environments, **provide a proof of concept (PoC)** or detailed steps to reproduce the vulnerability. I prioritize fixes that can be validated through real-world use and reproduction of the vulnerability in a real-world scenario.

### 2. Pull Request Process
To keep the main repository clean, I follow a "fork and pull" workflow:
* **Fork:** Fork this repository to your own account and work on your changes locally in your fork.

**Pull Request:** Once you have verified your solution by reproducing and resolving the issue in your local environment, open a pull request from your branch to the main branch of this repository.

**Transparency:** Link your pull request directly to the open security issue.

**Code Review:** I will personally review each contribution, focusing on:

- **Memory Safety:** Ensuring sensitive buffers are flushed (e.g., by initializing `Uint8List` to zero).

- **Cryptography:** Compliance with standard libraries (`pointycastle`, `archive`) and proper handling of sales/nonces.

- **Bridge Integrity:** Ensuring IPC bridge authentication remains intact.

### 3. Standards and Best Practices
**No Hardcoded Keys:** Never add hardcoded secrets or keys.

**Minimal Dependencies:** Keep dependencies to a minimum to reduce the attack surface.

**Stability in Real-World Environments:** While performance is important, never sacrifice security for speed.

## Reporting an Unpatched Issue
If you are working on a fix for a public issue, feel free to comment in the relevant thread so others know you are working on it. If you need help setting up the build environment and reproducing the issue, feel free to ask for guidance in the relevant thread.

-- *If you have any questions about a proposed security change, feel free to request a discussion in the relevant thread before starting the implementation.*
