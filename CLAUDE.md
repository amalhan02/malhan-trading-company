# Malhan Trading Company — shop management app

Internal app for a fertilizer & seed retail shop (Urea, DAP, SSP, TSP, Sulphur, Ammonium sulphate from the NFL dealership; seeds bought from the market). Several staff record transactions on their own phones and on a desktop.

Live site: https://amalhan02.github.io/malhan-trading-company/ (GitHub Pages, deploys from `main`, repository root).

## Architecture

- **No build step.** Plain HTML/CSS/JS in a single `index.html`. Keep it that way unless asked: the owner edits via GitHub's web UI and staff load it on old phones.
- **Backend: Supabase** (Postgres + Auth + Realtime). Schema, row-level security, triggers, RPCs and the audit log are in `schema.sql`. Treat it as idempotent: it must be safe to re-run in the SQL Editor.
- **`config.js`** holds `supabaseUrl` and the *anon/publishable* key only. Never commit a `service_role` / secret key anywhere.
- **`vendor/supabase.js`** is the bundled supabase-js v2 UMD build (global `supabase`). Don't swap it for a CDN link.
- **`sw.js`** caches only same-origin app files. It must never cache Supabase requests. Bump `CACHE` when app files change.

## Data model

One sync table, `records (shop_id, id, collection, data jsonb, deleted, created_by, updated_by, created_at, updated_at)`.

- `collection` is one of: products, suppliers, purchases, sales, customers, payments, expenses, adjustments.
- Server triggers own the timestamps and authorship (`clock_timestamp()`, `auth.uid()`). Clients can't set them.
- Deletes are soft (`deleted = true`). There are no DELETE policies.

Document shapes (the `data` field):

- **sales:** `{date, customerId, items:[{productId, qty, rate, cost}], discount, paid, mode, note}`. `cost` is the weighted average landed cost captured at the time of sale.
- **purchases:** `{date, supplierId, invoiceNo, items:[{productId, qty, rate}], freight, other, paid, note}`. Freight and other charges are spread equally per bag to get the landed cost.
- **payments:** `{kind: "customer" | "supplier", partyId, date, amount, mode, note}`
- **adjustments:** `{date, productId, qty (+/−), reason}`
- **products:** `{name, category, bagKg, mrp, lowStock, active}`
- **suppliers / customers / expenses:** simple flat objects

Derived values are computed on the client, never stored: stock, average cost, customer and supplier balances, profit.

## Sync engine (in index.html)

Offline-first. The local copy lives in IndexedDB (`malhan-<shopId>-<userId>`).

- `save()` and `removeRec()` write locally with `dirty: 1` and an incremented `v`.
- `push()` upserts in batches of 200 on `shop_id,id`. If the whole batch hits a row-level security error (42501), it retries one by one and reverts the rejected rows.
- `pull()` fetches rows with `updated_at > cursor − 2 min`, pages of 1000.
- Realtime `postgres_changes` on `records` provides live updates.
- Rules: local dirty rows win until their push is acknowledged. A server row is applied only if it's newer than the local copy.

## Roles

`members.role` is `owner`, `manager` or `staff`.

- Staff can update or delete only their own rows, and only within 24 hours. This is enforced by row-level security; the UI mirrors it with `canChange()`.
- Staff don't see profit, cost or reports (UI only: `seesProfit()`).
- Only the owner manages members and the join code (`rotate_join_code`).
- `create_shop` works only when no shop exists (one shop per project). `join_shop(code, name)` adds the caller as staff.

## Conventions

- Indian formatting: ₹ and `en-IN` number formatting, dates like "30 Sept 2026". Customer-facing WhatsApp text is in Hinglish.
- Mobile first. Tables use `class="t stackable"` with `data-l` labels so they collapse into cards below 900px.
- Keep the design tokens in `:root` (light and dark), use sentence-case labels, and don't add all-caps eyebrow labels.
- Everything the page renders from data goes through `esc()`.

## Testing

Before pushing:

1. Syntax-check the inline script: `node -e` with `new Function` on the extracted `<script>` body.
2. Run the Playwright end-to-end flow against a local `python3 -m http.server` with a mocked `vendor/supabase.js`. Covered: owner signup, create shop, staff joins with code, purchase, credit sale, cross-device sync, offline queue, reload.
3. For schema changes, test on local Postgres with a stubbed `auth` schema (`auth.uid()` reads `request.jwt.claim.sub`) before running in Supabase.

## Open ideas

- A reconciliation screen for the fertilizer POS machine.
- Seed lot numbers and expiry dates.
- GST invoices with HSN codes.
- Kharif and Rabi season reports.
- Hindi labels.
- Staff PIN lock.
