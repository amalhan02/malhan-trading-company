# Malhan Trading Company — shop management

Sales, purchases, stock, udhaar (khata), expenses and profit for a fertilizer and seed shop.
Multi-user with roles, live sync between devices, and full offline support.

This repository contains only the app's code. Shop data lives in the shop's private Supabase
database and on the devices of people who have signed in.

See **SETUP.md** to set it up.

| File | Purpose |
|---|---|
| `index.html` | The app |
| `config.js` | Your Supabase project URL and public key |
| `schema.sql` | Database tables, security rules and audit log — run once in Supabase |
| `sw.js`, `manifest.json`, icons | Offline support and home-screen install |
| `vendor/supabase.js` | Supabase client library (v2.117.2), bundled so the app doesn't depend on a third-party CDN |
