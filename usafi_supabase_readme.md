# USAFI Ledger Desk

Responsive Supabase-backed finance desk for daily USAFI balancing entries, workbook import, overview statistics, records review, and monthly reports.

## Files

- `usafi_app_improved.html` - redesigned main web app
- `assets/capitalbet-logo.png` - Capitalbet logo used by the app
- `usafi_supabase_schema.sql` - Supabase tables, views, indexes, triggers, and RLS policies

## Setup

1. Open Supabase SQL Editor.
2. Run the full contents of `usafi_supabase_schema.sql`.
3. Start a local static server from this folder:

```bash
python -m http.server 8080
```

4. Open:

```text
http://localhost:8080/usafi_app_improved.html
```

The app already contains the current Supabase project URL and publishable key:

```js
const SUPABASE_URL = 'https://rslhojrdkhpblkxickfv.supabase.co'
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_yfcNVQZKRc7uc8C3b8s7-g_YxFLR1us'
```

## First Import

1. Open the app.
2. Go to `Import`.
3. Choose `USAFI BALANCING SHEETS.xlsx`.
4. Review the detected entries.
5. Click `Import to Supabase`.

The importer reads each month sheet, extracts each daily block, skips empty template months, and saves:

- daily balance entry values
- approved expenses
- unapproved expenses
- status as `final`
- location as `USAFI`

Entries are upserted by `location + entry_date`, so re-importing updates the same days and refreshes their expense rows.

If Excel formatting causes some line-item expenses to be missed, the importer adds an approved adjustment row so the imported approved expense total matches the sheet's `EXPENSES` figure.

## Main Features

- Fully redesigned responsive command-bar workspace
- Dashboard with latest records and monthly grouped records
- Manual daily entry form
- Workbook importer
- Import expense reconciliation against the sheet `EXPENSES` total
- Automatic opening balance from the previous saved day
- Automatic cash-at-hand calculation, with password-protected manual override
- Saved entries table
- Monthly report cards
- Excel export
- PDF report export
- No login page
- Supabase public anon access for entries and expenses

## Calculation

```text
Expected closing =
  opening balance
  + normal sales
  + virtual sales
  + cash in
  - normal payout
  - virtual payout
  - cash out
  - approved expenses

Variance = expected closing - cash at hand
```

Unapproved expenses are saved and reported separately, but they are not deducted from expected closing.

## Database Notes

Core tables:

- `staff`
- `daily_balance_entries`
- `daily_balance_expenses`

Reporting views:

- `daily_balance_summary`
- `monthly_balance_summary`

The views are calculated from live entry and expense data, so reports stay accurate without a separate refresh job.

No-login mode makes the app faster to use, but anyone with the project URL and anon key can read and change entry data unless you add another access control layer later.
