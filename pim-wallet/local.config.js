// Local development config. Replace with your Firebase project settings.
// This file defines globals expected by index.html
// Do NOT commit real secrets.

window.__firebase_config = JSON.stringify({
  apiKey: "",
  authDomain: "",
  projectId: "",
  storageBucket: "",
  messagingSenderId: "",
  appId: ""
});

window.__app_id = "pim-vault-stable";

// GitLab OAuth (optional overrides)
// If login isn't working, set these to match your GitLab OAuth Application.
// Redirect URI must match the page URL exactly (e.g. http://localhost:8000/pim-wallet/index.html).
//
window.__gitlab_base_url = "https://gitlab.com";
window.__gitlab_client_id = "96cee0999c5136a8f06e2fa8148e6e162d5154bda1a767c60aaf1bea3a7fe664";
//
// Optional: only if your app/instance requires it.
// window.__gitlab_client_secret = "YOUR_GITLAB_OAUTH_CLIENT_SECRET";