# Security Policy

Sword is designed for controlled local or internal-network operation.

## Supported Version

The latest public version is the supported version.

## Private Data

Never publish:

- `data/store.json`
- files inside `backups/`
- runtime logs
- archives containing real stores
- IP lists, hostnames, user records, password hashes or session tokens

Use `data/store.example.json` as the only public store example.

## Reporting

Open a GitHub issue with a minimal reproduction. Do not include private infrastructure data or credentials.
