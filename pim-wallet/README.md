# PIM Wallet – GitLab Login Setup

This page supports GitLab OAuth 2.0 (PKCE) so anyone can connect using gitlab.com or a self‑hosted GitLab.

## 1) Run locally

Use any static server. From the workspace root:

```bash
python3 -m http.server 8000 --directory "/home/kdbbbu/WebDev/Apple Watch profit or loss notifier"
```

Open:

- http://localhost:8000/pim-wallet/index.html

## 2) Create a GitLab OAuth Application

In GitLab (gitlab.com or your instance):

- User Settings → Applications → Add new application
- Name: "PIM Wallet Local"
- Redirect URI: `http://localhost:8000/pim-wallet/index.html` (must match exactly)
- Scopes: `read_user`, `profile`, `email`
- Save and copy the Application ID

Notes:
- For self‑hosted, use your instance URL as Base URL (e.g., `https://gitlab.example.com`).
- GitLab 15.1+ supports CORS on `/oauth/token` which is required for the browser token exchange.

## 3) Configure Firebase (Optional)

The app can work without Firebase for GitLab login, but wallet features expect a Firebase project.

Edit `pim-wallet/local.config.js` and fill your Firebase settings:

```js
window.__firebase_config = JSON.stringify({
  apiKey: "…",
  authDomain: "…",
  projectId: "…",
  storageBucket: "…",
  messagingSenderId: "…",
  appId: "…"
});
window.__app_id = "pim-vault-stable";
```

## 4) Use the app

- Open the page, in the auth screen fill:
  - Base URL: `https://gitlab.com` or your instance
  - OAuth Application ID: paste the ID
- Click "LOGIN WITH GITLAB" and complete the consent.
- After redirect, you should see `GitLab: <username>` in the header.

## 5) Troubleshooting

- 400 redirect_uri mismatch: ensure the Redirect URI in GitLab matches exactly the page URL.
- CORS error on `/oauth/token`: ensure your instance is recent enough and not blocking preflight. GitLab.com works.
- Self‑hosted with custom domain: use the exact base URL, no trailing slash.
- Blank Firebase config: wallet data views may be empty; GitLab login still works.
- Clear session: use the top‑right logout; it clears GitLab tokens and UI.

## 6) Security

- PKCE is used; no client secret is stored in the browser.
- Tokens are stored in `sessionStorage` and cleared on logout/tab close.
- Only minimal scopes are requested.
