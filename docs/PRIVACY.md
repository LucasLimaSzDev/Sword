# Public Repository Privacy Notes

The public repository intentionally contains only source code, documentation and a clean example store.

The real runtime store belongs only on the local machine running Sword:

```text
data/store.json
```

That file can contain devices, IPs, hostnames, users, password hashes, sessions, audit history, alerts and operational incidents. It must never be committed.
