# Malhan Trading Company — setup guide

About 20 minutes, done once by the owner (or you). After that, staff only need the link and the join code.

## How it fits together

- **GitHub Pages** hosts the app (the code only, no shop data).
- **Supabase** is the shop's private database. Your own free project; only people who sign in and join the shop can read it.
- **Each phone** keeps a working copy, so the app works without internet and syncs when back online.

## 1. Create the database (Supabase)

1. Go to https://supabase.com, sign up, and click **New project**.
   - Name: `malhan-trading`
   - Database password: generate one and save it somewhere safe
   - Region: **Mumbai (ap-south-1)** — closest to the shop
2. When the project is ready, open **SQL Editor → New query**, paste the whole of `schema.sql`, and click **Run**. It should say "Success".
3. Open **Authentication → URL Configuration**:
   - Site URL: `https://amalhan02.github.io/malhan-trading-company/`
   - Redirect URLs: add the same URL
4. Optional, but easier for staff: **Authentication → Sign In / Providers → Email** → turn off **Confirm email**.
   (If you keep it on, each person must click a link in their email before they can sign in.)

## 2. Connect the app to the database

1. In Supabase, open **Project Settings → API** (or **API Keys**).
2. Copy the **Project URL** and the **anon / publishable** key.
3. Open `config.js` and paste them in:

       supabaseUrl: "https://xxxxxxxx.supabase.co",
       supabaseAnonKey: "eyJ...",

   The anon key is meant to be public — security comes from sign-in and the database rules.
   **Never** put the `service_role` / secret key in this file.

## 3. Publish on GitHub

Upload every file and the `vendor` folder to the root of
https://github.com/amalhan02/malhan-trading-company (replace the old files), then
**Settings → Pages → Deploy from a branch → main → / (root) → Save**.

The app is at https://amalhan02.github.io/malhan-trading-company/

## 4. First sign-in (owner)

1. Open the link, tap **Create an account**, enter your name, email and a password.
2. Open **I'm the owner — set up the shop** and tap **Create shop**.
   This works only once, for the first person. Products (Urea, DAP, SSP, TSP, Sulphur,
   Ammonium sulphate) and suppliers (NFL, Seed market) are added automatically.
3. Go to **Setup → Products** and fill in the MRP and reorder level for each item.
4. Enter opening stock: **Stock → Adjust stock → Opening stock**, one product at a time.

## 5. Add staff

1. **Setup → Team → Share on WhatsApp** sends the link and the join code.
2. Each person creates their own account and taps **Join shop** with the code.
   They join as **Staff**. Change anyone to **Manager** from the Team page.
3. Once everyone has joined, tap **New code** so the old code stops working.

On iPhone: open the link in Safari → Share → **Add to Home Screen**.
On Android: open in Chrome → menu → **Install app** / **Add to Home screen**.

## Roles

| | Owner | Manager | Staff |
|---|---|---|---|
| Record sales, purchases, payments, expenses | ✓ | ✓ | ✓ |
| Edit/delete own entries within 24 hours | ✓ | ✓ | ✓ |
| Edit/delete anyone's entries | ✓ | ✓ | |
| See profit, cost and reports | ✓ | ✓ | |
| Products and suppliers | ✓ | ✓ | |
| Activity log | ✓ | ✓ | |
| Team, roles, join code | ✓ | | |

Staff can still see purchase rates they enter; hiding profit is about keeping margins off their screens.

## Moving data from the earlier offline version

On the old device: **More → Backup & restore → Save full backup**.
In the new app, signed in as owner: **Setup → Backup & export → Import from backup file**.

## Backups and safety

- Supabase keeps the master copy. On the free plan, take your own backup regularly:
  **Setup → Backup & export → Full backup (JSON)**.
- Free Supabase projects pause after a week with no activity. A shop using the app daily
  won't hit this; if it happens, open the Supabase dashboard and click **Restore project**.
- Removing someone from the Team page cuts their access immediately. Their past entries stay.
- Every create, edit and delete is recorded in the activity log with who did it and when.

## Updating the app later

Replace `index.html` (or other files) in the GitHub repository. Devices pick up the new version
the next time they open the app with internet. Shop data is never affected by app updates.
