# Security Policy

## Reporting a vulnerability

If you find a security issue in Beacon (for example key leakage, unsafe shell execution, or privilege escalation), **do not** open a public issue with exploit details.

Email or message the maintainer privately ([@H3ctorYpz](https://github.com/H3ctorYpz)), and allow reasonable time for a fix before public disclosure.

## Secrets

- API keys are stored in the macOS Keychain (with a debug UserDefaults fallback).
- Never commit keys, tokens, or production credentials.
- Rotating a leaked provider key is your responsibility with that provider.

## Agent mode

When **Permitir herramientas del Mac** is enabled, Beacon can run terminal commands, read/write files, and run AppleScript **after** user approval for sensitive tools. Treat agent mode like giving a helper limited access to your Mac — review prompts before allowing.
