# ZenSched Billboard Photo-Audit Reference Kit

A copy-pasteable setup for a small billboard / street-furniture photo-audit shop (an owner plus contractor auditors, or an in-house posting-proof team) that wants an AI assistant to run face dispatch, GPS-verified Proof Records, auditor pay, and buyer invoicing. ZenSched handles the live schedule, the auditor's phone app, GPS check-ins at the face, and the photo-plus-checklist Proof Record. A small local database on your computer holds your campaigns, faces (places), visit status, proof summaries, invoices, and pay runs.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("set up the Acme September flight", "give Jordan the two Dallas faces Thursday", "pull this week's proofs", "invoice Acme", "run auditor pay") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that an auditor was at the face, a Proof Record (up to 2 photos of the creative, Yes/No/Partial match to the brief, a damage note), a local extract of mismatches and damage, and invoices built from approved visits.

**What it is not:**

- **Not a legal posting affidavit.** The Proof Record has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like someone had sworn something. Submitting the form is just submitting the form. Contract disputes still need whatever your counsel wants.
- **Not a burned-in GPS stamp.** ZenSched stores date, time, and distance-from-the-pin on the server. It does **not** render those onto the image itself. If a buyer or a court wants a readable stamp on the photo, the auditor still uses a camera overlay.
- **Not GeoPath, OAAA, or Nielsen measurement.** This kit does not produce ratings, circulation, or a certified audit. It is a photo log with a GPS punch.
- **Not an inventory / avail / proposal tool.** Faces here are places you send an auditor to, not a plant book, not a proposal, and not a vinyl or illumination log.

If any of those is a deal-breaker, this kit is not for you. If you want campaign → face → visit dispatch, door-GPS (well, shoulder-GPS), and a local extract you can file next to the real affidavit, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (faces with GPS coordinates; the check-in radius is a **policy** setting)
- Workers (auditors with the mobile app)
- Events (one per face per campaign flight, at most 60 days)
- Shifts (each assigned audit visit, with a push notification)
- GPS punches (check-in / check-out with distance-from-the-pin verification)
- The Proof Record form (creative photo max 2, matches brief, damage) and every submission
- Timesheets (rarely needed here; auditors are paid per visit)

**Local SQLite database (`billboard.db`, on your computer):**

- Campaigns: advertiser, flight dates, daily window, quota per face, fees, creative brief
- Faces (places): plant / face codes, media type, address, per-face time zone, access notes that **never leave your computer**
- Campaign × face rows with the ZenSched event for that flight
- Auditors: contact, home city, pay handle, ZenSched worker id
- Visits: one row per audit visit, open → assigned → completed / no-show / rejected / cancelled, with punch stamps, matches-brief, damage, photo URLs, QA, invoiced and paid flags
- Buyer invoices and auditor payouts
- Your settings (default time zone, default visit length, Proof Record form id, invoice prefix)

**Never duplicated:** the live schedule, punches, and the original submissions and creative photos stay in ZenSched. The local database stores *references* to them plus a short per-visit summary so you can answer "what's wrong on Acme" without paying to re-read reports.

### Privacy note

Highway-shoulder / parking / ladder / gate notes live only in `faces.access_notes`. Auditor pay handles live only in `auditors.pay_handle`. Buyer billing contacts and fees live only on `campaigns`. `SKILL.md` forbids the AI from putting any of those into a ZenSched field. The creative name **may** appear on the event title — auditors have to know what should be on the board. Give access notes to your auditor yourself.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `event_create`, `shift_create`, `form_submissions`, `shift_list`, `policy_update`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `billboard.db` on your computer.

When a buyer sends a face list and a flight, you paste them. The AI creates the campaign locally, adds each face to the place cache (geocoding only the ones it has never seen), attaches the Proof Record to one ≤60-day event per face, and opens the audit visits from the quota (posting, or posting + mid-flight, or posting + mid + take-down). You say "give Jordan the two Dallas faces Thursday morning" and the AI creates one shift per visit. Jordan sees the stops in the app, checks in at the face (GPS-verified), photographs the creative, marks whether it matches the brief, notes damage, and checks out. Later you say "pull this week's proofs" and the AI records the summaries, leads with mismatches and late punches, and you approve or reject. Approved visits flow to the buyer invoice and the auditor pay sheet. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical visit costs about **$0.35** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading a Proof Record that has photos $0.15. Geocoding a new face is $0.03 once. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\billboard`
- Mac: `/Users/yourname/billboard`

The database file will be created automatically inside this folder the first time the AI uses it. It will hold buyer contracts and auditor pay details; keep it backed up.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\billboard.db` (Windows) or `/billboard.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "billboard-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/billboard/billboard.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\billboard\\billboard.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Billboard Audit Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my billboard database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `billboard.db` file now exists in your folder with default settings (Central time, 15-minute visits, 200 m recommended radius, net-30 invoices) you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 billboard.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Sightline Audits in Dallas, Texas (Central time). Save that in settings, set the check-in radius to 200 m, and set up the Proof Record form.

It writes those to the `settings` table, sets the check-in policy on ZenSched (free), creates the Proof Record form (free), and saves the form id so every visit gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=200` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per face. With geofencing on it raises anything under 100 m to about 91 m (300 ft). Highway bulletins, frontage-road pull-offs, and pins that land on the roadway routinely put the auditor 50–200 m from the geocoded pin, which is why the kit recommends 200 m. Widen the radius with `policy_update(0, {"checkin_radius_m": N})`, never "on that location". If a pin lands on the road rather than the structure, the AI can move it (`location_update`, free) or have ZenSched pick the structure (`location_refine`, $0.10). `remote_checkin` turns GPS verification off for **every** campaign on that policy and should not be flipped on policy 0; see Troubleshooting and the brand/policy recipe in `SKILL.md` if you also run drive-by photos.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a face location (geocoding, $0.03, once per face ever), inviting an auditor ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Proof Record ($0.05, or $0.15 when it has photos; each submission is billed once, ever). Creating forms, events, and shifts, and listing them, is free. When a metered call happens without funds, the AI gets a `payment_required` response and tells you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical visit is about $0.35 (in + out + photo record). Two new faces and four visits is about $1.46; the AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "New campaign. Advertiser Acme Coffee, contact Priya Nair. Acme Iced cup on black. Sep 8 through Oct 5, any day 7 to 7, posting plus mid-flight. $40 a visit to them, auditors get $20. Faces: SL-DAL-1102 N, bulletin, I-35N at Commerce, Dallas TX 75202 / SL-DAL-880 A, street furniture, Elm and Griffin, Dallas TX 75201. Shoulder pull-off on the I-35 face; shelter has a curb cut on Elm."
- "Invite Jordan Hale, jordan@example.com, Dallas, PayPal same email."
- "Give Jordan the two Dallas posting visits Thursday morning."
- "Fill the open visits."
- "Pull this week's proofs."
- "Approve the I-35 bulletin. Reject the shelter, lower third is still last-flight vinyl. Reopen it."
- "What's wrong on Acme?"
- "How's the Acme campaign doing?"
- "Invoice Acme and send them the proofs."
- "Run auditor pay."
- "Acme paid INV-2026-0001."

See `QUICKSTART.md` for the first-flight walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Invoice Acme" records the invoice in your database (number, date, due date from the campaign's payment terms, visit count, fees, which visits) and the AI writes out a plain-text invoice you can paste into an email, with a line per approved visit (date, face label, posting / mid-flight / take-down, fee) and a note that every visit was GPS-verified with timestamped creative photos. It does **not** generate a PDF, email it for you, or collect payment, and it does **not** claim to be an affidavit. Auditor names never appear on it. When the buyer pays, tell the AI ("Acme paid INV-2026-0001") and it marks it paid.

### What "auditor pay" means here

"Run auditor pay" totals approved visits per auditor, records a payout row with the visit list, and writes a pay sheet with each auditor's pay handle. You pay them outside the kit and say "paid". Rejected and no-show visits are not on the sheet.

## Mobile app for auditors

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite an auditor, they get an email, install the app, and can immediately see their assigned visits, check in and out with GPS verification, and fill in the Proof Record. The creative photo is a required field (up to 2). There is no signature step — they tap Submit. The brief and the shoulder / lot notes are something you tell them yourself.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `billboard-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| Denver visit created at the wrong hour | Face has the wrong `tz_offset` | "Set that face to Mountain time (-06:00)"; the AI fixes the face and updates the shift |
| AI refuses a campaign longer than 60 days | Working as intended; ZenSched events are capped at 60 days | Ask for it as monthly flights; the AI creates one campaign row and one set of events per window |
| Auditor's check-in not GPS-verified at a highway bulletin | Auditor was outside the policy radius, or the pin is on the roadway | "Set the check-in radius to 300 m" (`policy_update`, account-wide), or "move the I-35 pin onto the structure" (`location_update`, free), or `location_refine` ($0.10). Do **not** ask to widen the radius "on that location" |
| You also run drive-by / phone photos | Those cannot have a walked-up GPS punch | Keep policy 0 geofenced for roadside stops; ask the AI to give drive-by campaigns their own brand and policy (`policy_create` → `brand_create(policy_id=…)` → `event_create(brand_id=…)`) rather than flipping `remote_checkin` account-wide |
| Auditor forgot to check out | Shift still `checked_in` | Tell the AI to use the form's submission time as check-out; ask for a check-out reminder (`checkout_reminder_min_after`) |
| Auditor does not see the Proof Record | Form not assigned to that face's event | "Attach the Proof Record to the I-35 event" (`form_assign`) |
| "What's wrong on Acme" comes back empty | Visits not recorded yet, or everything matched with no damage | "Pull this week's proofs" first; `proof_exceptions` only lists No / Partial / damage |
| A visit is flagged but the buyer is fine with it | Working as intended; flags are for you, not automatic rejections | Approve it and put the reason in the QA note |
| Same face pasted twice in a CSV | Plant / address written differently | The AI normalizes plant + face + city; if it still created two faces, say "these are the same face" and it merges them (one geocode is wasted, $0.03) |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a shoulder / gate note in ZenSched | Working as intended | Give it to the auditor directly |
| AI offers an affidavit, GeoPath report, or OAAA certificate | It shouldn't | This kit does not produce those |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (locations, events, shifts, punches, forms, submissions); SQLite is authoritative for the commercial model (campaigns, fees, quotas, face cache, auditor pool, visit lifecycle, Proof Record summaries, QA, billing, payouts); each side stores only the other's **integer** IDs plus the few per-visit values billing needs. The confidentiality boundary is enforced by data placement and by `SKILL.md` rules 1–2.

**Data model decisions.**

- **campaigns → faces (places) → audit visits.** `faces` is a place cache, `UNIQUE (normalized_key)`; `SKILL.md` gives the normalization recipe. `campaign_faces` (`UNIQUE (campaign_id, face_id)`) is the booking of a face onto a flight and holds `zensched_event_id`. `visits` hang off `campaign_faces`.
- One ZenSched **location** per face, permanent, stored on `faces.zensched_location_id` as an integer. Created with `location_create(name=<face_label>, street_address=..., checkin_radius_m=<settings default>, idempotency_key="loc-face-{face_id}")`. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **One event per face per campaign, never more than 60 days.** `campaigns.flight_start` / `flight_end` are the event dates; a `CHECK` rejects `flight_end` more than 59 days after `flight_start`, which forces long bookings into one campaign row per window (the kit's answer to the 60-day event cap; there is no rolling `event_needs_roll` on the face because a flight never outlives its events). `event_create(location_id, title="{creative} - {face_label}", start_date=flight_start, end_date=flight_end, idempotency_key="event-cf-{campaign_face_id}-{YYYYMMDD}")`, then `form_assign(form_id, event_id=...)`. `visits_upcoming.needs_event` flips when the row has no event or `event_valid_until` is before the visit date.
- **Per-face time zone.** `faces.tz_offset` is `CHECK`-constrained to `[+-]HH:MM`. `visits.scheduled_start` / `scheduled_end` are face-local wall-clock (`YYYY-MM-DDTHH:MM:SS`, no offset) and `visits_upcoming` builds `start_iso` / `end_iso` as `scheduled_start || tz_offset`.
- **One Proof Record for the org**, id on `settings.proof_record_form_id`, created with `form_create(title, fields_json, idempotency_key="form-proof-record")`. The exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Four fields, every one with an explicit `identifier`: section `sec_proof`, photo `creative_up` (`max_images` 2, required), select `matches_brief` (`Yes` / `No` / `Partial` → keys `yes`, `no`, `partial`), textarea `damage`. **No `signature` field.** Option keys are well under 30 characters.
- **Visit lifecycle.** `visits.status` is `open | assigned | completed | no_show | rejected | cancelled`; `visit_kind` is `posting | mid_flight | take_down | make_good | spot`; `qa_status` is `pending | approved | rejected`; `matches_brief` is `Yes | No | Partial`; all `CHECK`-constrained. `zensched_shift_id` is `UNIQUE`. Never reuse a row that has a shift id. Quota 1 / 2 / 3 maps to posting / + mid / + take-down.
- **Fraud and proof flags are a view.** `visits_flagged` returns completed visits with late / early / no punch / short / mismatch / damage. `proof_exceptions` is the owner's extract of No / Partial / damage rows. A flag is information for QA; approving a flagged visit with a note is supported.
- `duration_minutes` is filled by two triggers whenever it is NULL and both punch stamps exist. `fill_visit_auditor` sets `auditor_id` from `zensched_worker_id` when the agent leaves it NULL.
- **Money.** `visits_to_invoice` groups approved, uninvoiced visits per campaign with `SUM(client_fee)`; `auditor_pay_due` does the same per auditor. Fees are read live from the campaign, not snapshotted. `invoices.invoice_number` is auto-assigned as `{prefix}-{YYYY}-{0001}`; `invoices_outstanding` adds `days_overdue` and `aging_bucket`.
- **Drive-by / phone photos share the account.** `remote_checkin` is policy-scoped. Keep policy 0 geofenced; `policy_create` → `brand_create(policy_id=…)` → `event_create(brand_id=…)` for the remote campaigns.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-face-{face_id}`
- event: `event-cf-{campaign_face_id}-{YYYYMMDD flight start}`
- shift: `shift-visit-{visit_id}`
- cancel: `cancel-shift-{shift_id}`
- worker: `worker-{email}`
- form: `form-proof-record`; assignment: `assign-proof-record-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset, never `Z`. The offset is the **face's** (`faces.tz_offset`).

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media; the creative photo makes every visit a media read), once per submission ever; replays are free. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent.

**Schema test.** The schema was verified by splitting the file into its 48 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 8 tables, 10 views, and 8 triggers present; every view on an empty database; integer types on ZenSched ID columns; `UNIQUE (normalized_key)`, `UNIQUE (campaign_id, face_id)`, `UNIQUE` on `zensched_shift_id`, `auditors.email`, and `auditors.zensched_worker_id`; `visits_upcoming` building `start_iso` / `end_iso` from a `-05:00` and a `-06:00` face, the `shift-visit-{id}` key, `needs_location`, and `needs_event` flipping on a stale `event_valid_until`; `visits_open` days-left math; `visits_overdue`; `visits_flagged` catching a 40-minute-late check-in, a short visit, an early check-in, a completed visit with no punch, Partial+damage, and No, while ignoring on-time Yes visits and a 10-minute-early one; `proof_exceptions` including only No / Partial / damage; the duration trigger on insert and update, across mixed offsets, refilling after NULL, and never overwriting an explicit value; `fill_visit_auditor` from `zensched_worker_id`; `campaign_progress` counts; `visits_to_invoice` and `auditor_pay_due` math; invoice numbering (auto `INV-2026-0001`, explicit number kept); all five aging buckets and `days_overdue`; `auditor_reliability` including an auditor with no visits; every `CHECK` (flight length both ways, window times, weekday mask, quota, campaign status, `tz_offset` including rejecting `Z`, `media_type`, `scheduled_*` rejecting an offset and a space separator, visit status, visit kind, QA status, `matches_brief` labels); the four `updated_at` triggers; foreign keys, cascade from campaign, and set-null from auditor. The Proof Record form in `SKILL.md` was run through ZenSched's `_validate_fields` and accepted (4 fields, no signature, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters). 114 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
