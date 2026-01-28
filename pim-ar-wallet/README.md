# PIM AR Wallet (Fresh Build)

This folder is a **fresh, standalone** single-page app (no backend) that demonstrates:
- GitLab OAuth login (PKCE) for access to the main page
- A simulated wallet (balances, send/receive, transaction history)
- A send + coin-converter panel
  - Supported demo tokens: **PIM, ETH, USDT, BCH (Bitcoin Cash)**
  - **PIM is fixed at 0.10 USDT per 1 PIM (demo peg)**
  - ETH/BCH use best-effort live rates (fallback included)
- A **safe** “bin/folder scanner” that only inspects **directory structure + filenames/extensions** in a user-selected folder
  - It does **not** read or upload file contents
  - It mints local “on-chain artifacts” (a hash of scan metadata) and stores them in your browser storage

## Run locally
From the repo root:

```bash
python3 -m http.server 8001
```

Open:
- `http://localhost:8001/pim-ar-wallet/`

## GitLab OAuth setup
Create an OAuth application in GitLab (gitlab.com or self-hosted):
- Redirect URI: exactly the page URL you load, e.g. `http://localhost:8001/pim-ar-wallet/`
- Scopes: `read_user` (and optionally `email`)

In the app UI, enter:
- GitLab Base URL (e.g. `https://gitlab.com`)
- Application ID (client_id)
- (Optional) client_secret if your app is confidential

## Safety and privacy
- The scanner runs **only after the user picks a directory**.
- It reads **only metadata** (names, extensions, sizes when available).
- No blockchain transactions happen in this demo; “on-chain” artifacts are simulated as hashes.

## Notes
This is a demo environment. Nothing here is a guarantee of profit/income.
