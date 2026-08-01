<div align="center">

<img src="Resources/Icon.png" width="128" alt="Proxy Checker">

# Proxy Checker

**A fast, native proxy checker for Apple silicon Macs.**

Check thousands of proxies concurrently, resolve their protocol, location and
anonymity level, and export exactly the subset you need.

[![Build](https://github.com/NezzDevs/Mac-Proxy-Checker/actions/workflows/build.yml/badge.svg)](https://github.com/NezzDevs/Mac-Proxy-Checker/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

</div>

---

## Install

Download **ProxyChecker.dmg** from [**Releases**](https://github.com/NezzDevs/Mac-Proxy-Checker/releases), open it, and drag **Proxy Checker** into Applications.

The build is ad-hoc signed rather than notarized, so Gatekeeper blocks the first launch. Clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine "/Applications/Proxy Checker.app"
```

Requires **macOS 14 or later** on Apple silicon.

---

## Features

| | |
|---|---|
| **Concurrent checking** | 1–1000 simultaneous checks, backed by Swift structured concurrency |
| **Protocol detection** | Identifies HTTP, HTTPS, SOCKS4 and SOCKS5 over a raw socket, before any HTTP request |
| **Custom target** | Point every check at any URL; the round trip is the reported speed |
| **Response codes** | Shows what the target actually returned — 200, 403, 429 — per proxy |
| **Geolocation** | Country, state and ISP, resolved in bulk and cached to disk |
| **Anonymity levels** | Classifies elite, anonymous and transparent proxies |
| **Authentication** | `user:pass` for both HTTP and SOCKS proxies |
| **Custom headers** | Add `Referer`, `Origin`, `Cookie` or anything else to every request |
| **Flexible export** | Six line formats, five grouping schemes, filterable on every field |

---

## Usage

### Importing

**Add Proxies** accepts a pasted list or a file, and the window accepts drops. Every common format parses:

```
1.2.3.4:8080
1.2.3.4:8080:user:pass
user:pass@1.2.3.4:8080
socks5://user:pass@1.2.3.4:1080
http://1.2.3.4:3128
1.2.3.4,8080,user,pass
```

Comments (`#`, `//`) and duplicates are dropped automatically. A `scheme://` prefix is taken as the declared protocol, which skips detection and speeds up the run.

### Checking

Press **Start** (`⌘R`) to check everything, or use its menu for **Retry Failed**. **Stop** is `⌘.`

The status bar counts Good, Slow, Timeout and Failed live — click any chip to filter the table to it. Results land sorted fastest-first, and a card summarises the run when it finishes.

Click the **target chip** in the status bar to change the site every proxy is checked against. Defaults to Google.

### Exporting

Filter by status, protocol, country, state, anonymity and a speed ceiling, then choose a line format:

| Format | Output |
|---|---|
| `hostPort` | `1.2.3.4:8080` |
| `hostPortUserPass` | `1.2.3.4:8080:user:pass` |
| `userPassAtHost` | `user:pass@1.2.3.4:8080` |
| `schemeURL` | `socks5://user:pass@1.2.3.4:1080` |
| CSV | Every field, including response code and exit IP |
| JSON | Every field, structured |

Splitting writes one file per protocol, country, state, anonymity level or speed band — `proxies_socks5.txt`, `proxies_united-states.txt`, `proxies_elite.txt`. **Copy** sends the same selection to the clipboard instead.

---

## Settings

| Setting | Effect |
|---|---|
| **Threads** | Concurrent checks. 100–300 suits Apple silicon. |
| **Timeout** | Past this, a proxy is **Timeout** rather than **Failed**. |
| **Slow above** | Working proxies over this latency are **Slow** rather than **Good**. |
| **Retries** | Extra attempts for failures and timeouts. |
| **Detection** | Auto-detect, or force a single protocol. |
| **Location** | Country, state and ISP. Choose whether to locate by proxy address or exit IP. |
| **Security type** | Adds a judge request per proxy to classify anonymity. |
| **User agent** | Sent with every check. |
| **Custom headers** | Extra headers, overriding same-named defaults. |

---

## How it works

### Protocol detection

Before any HTTP request, the checker opens a raw TCP socket and speaks each protocol in turn:

1. **SOCKS5** — sends the greeting `05 02 00 02`; a SOCKS5 server answers `05 <method>`.
2. **HTTP** — sends a `CONNECT` and looks for an `HTTP/1.x` status line. A `407` still confirms an HTTP proxy.
3. **SOCKS4** — sends a connect request and looks for `00 5A`–`00 5D`.

An HTTP proxy cannot fake the SOCKS5 reply byte and vice versa, so there are no false positives between them. Detection is skipped entirely when the list declares a scheme or a protocol is forced.

### Speed and status

Speed is the wall-clock round trip of the target request through the proxy, measured with `DispatchTime`.

The status column shows the HTTP code the target returned. Only codes the *proxy* emits count as failure — 401, 407, 502, 503. A 403 or 404 comes from the target, meaning the tunnel worked and the site turned that IP away, which is a materially different result.

### Geolocation

Locations resolve in a single bulk pass after the run rather than per proxy. ip-api's free tier permits 45 single lookups a minute but 15 batches of 100, so batching alone is a 33× gain. On top of that:

- only working proxies are resolved,
- duplicate exit IPs collapse to one lookup,
- results are cached to disk for 30 days, so repeat runs cost nothing.

The `X-Rl` and `X-Ttl` response headers are honoured as the API requires: at zero remaining, the service waits out the window instead of earning a ban.

Two modes, under **Settings → Locate by**:

- **Proxy address** *(default)* resolves each proxy's hostname locally over DNS. Nothing is sent through the proxies at all.
- **Exit IP** asks each proxy which address it exits from, then batches those. Slower, but correct for rotating gateways where the address you dial and the node you exit from differ.

### Anonymity

Your public IP is fetched once at the start of a run, then each proxy requests a judge page that echoes request headers back:

| Result | Classification |
|---|---|
| Your IP appears in the response | **Transparent** |
| Forwarding headers present, your IP absent | **Anonymous** |
| Neither | **Elite** |

### Authentication

HTTP proxy credentials go through a `URLSessionTaskDelegate`; SOCKS credentials use the CFStream SOCKS properties. Self-signed certificates on proxy endpoints are accepted, since certificate validity is not what's being measured.

---

## Building from source

Requires Xcode 15 or the Swift 5.9 toolchain.

```bash
git clone https://github.com/NezzDevs/Mac-Proxy-Checker.git
cd Mac-Proxy-Checker
./build-app.sh         # → "Proxy Checker.app"
./make-dmg.sh          # → ProxyChecker.dmg (optional)
open "Proxy Checker.app"
```

> **Build the bundle rather than running `swift run`.** App Transport Security reads the bundle's `Info.plist`, which is what permits plain `http://` targets such as `ip-api.com` and `azenv.net`. A loose binary has no plist, so those requests are blocked before they ever reach a proxy.

Pushing a tag builds and publishes a release automatically:

```bash
git tag v1.0 && git push --tags
```

---

## Notes and limitations

- **ip-api's free tier is non-commercial only** and offers no HTTPS. For commercial use or unlimited queries, their pro service is the supported path.
- **`azenv.net` is the default anonymity judge** and goes down occasionally. Any page that echoes request headers works — swap it in settings.
- **Some headers cannot be overridden.** URLSession populates `Host`, `Connection`, `Content-Length`, `Authorization` and the proxy-auth pair itself. The header editor flags these rather than letting them fail silently.
- **Very high thread counts are bounded by your machine, not the app.** The file descriptor limit is raised at launch (256 → 16384), but sustained throughput past a few hundred threads depends on your network rather than the checker.

---

## License

Licensed under the [GNU General Public License v3.0](LICENSE).

You are free to use, modify and redistribute this software. If you distribute a
modified version, you must release its complete source under the same license,
preserve the copyright notices, and state what you changed. Closed-source forks
are not permitted.

Contributions are welcome and are accepted under the same terms.
