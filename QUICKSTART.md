# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified posting proof plus a local extract of the Proof Record. It is **not** a legal affidavit, **not** a burned-in GPS stamp, and **not** a GeoPath / OAAA audit.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\billboard` (Windows) or `/Users/yourname/billboard` (Mac). Note the full path. It will hold buyer fees and auditor pay details, so keep it backed up.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\billboard\\billboard.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Sightline Audits". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my billboard database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Sightline Audits in Dallas, Texas, Central time. Save that to settings, set the check-in radius to 200 m, and create the Proof Record form.

The AI saves your settings, sets the ZenSched check-in policy (free; 200 m, GPS on — widen later with `policy_update`, never "on that location"), and calls `form_create` once (free) to build the Proof Record: creative photo (max 2, required), matches brief (Yes / No / Partial), damage notes. No signature. It stores the form id so every visit gets it.

## 6. Add your first campaign

> New campaign. Advertiser Acme Coffee, contact Priya Nair, priya@acme.example, billing ap@acme.example, net 30. Creative: Acme Iced cup on black. Sep 8 through Oct 5, any day 7 to 7, posting plus mid-flight. $40 a visit to them, auditors get $20, visits at least 5 minutes. Faces: SL-DAL-1102 N, bulletin, I-35N at Commerce St, Dallas TX 75202, dusk to dawn, shoulder pull-off southbound / SL-DAL-880 A, street furniture, Elm and Griffin, Dallas TX 75201, curb cut on Elm. Brief: photograph the whole face so the cup is readable; note tears, dark panels, graffiti, or a dark digital.

Behind the scenes the AI inserts the campaign and two faces, asks before geocoding ($0.06, may trigger the $5 activation deposit the first time), creates one ≤60-day `event_create` per face, attaches the Proof Record with `form_assign`, and opens four visits (posting + mid-flight on each face). Shoulder / curb notes go only into the local database. You just see a confirmation.

## 7. Invite your auditor

> Invite Jordan Hale at jordan@example.com, Dallas, PayPal same email, and make them the default.

Jordan gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give them the shoulder / curb notes yourself; the AI will not put them in ZenSched.

## 8. Assign the posting visits

> Give Jordan the two Dallas posting visits Thursday morning.

The AI picks Thursday 9/10 inside the 7–7 window, creates one shift per visit on ZenSched in Dallas time (`-05:00`), and confirms. Jordan gets a push notification per visit with the Proof Record attached. Each completed visit is about $0.35 once they punch and you read the photo record.

Or say "fill the open visits" and the AI proposes who should take what, by home city and track record, and waits for your yes.

## 9. After the work is done

> Pull this week's proofs.

The AI pulls the completed, GPS-verified shifts (free) and the Proof Records from ZenSched (metered, so it tells you the cost first), saves matches-brief / damage / photo URLs locally, and leads with anything that did not match or that noted damage.

> Approve the I-35 bulletin. The shelter is Partial — reopen it as a make-good.

Approved visits go on the buyer invoice and the auditor pay sheet. The rejected shelter visit stays on the history row and a fresh open visit is created.

> What's wrong on Acme? Then invoice them and run auditor pay.

A local extract (not a re-read), a plain-text invoice you can paste into an email, and a pay sheet with Jordan's PayPal handle. You pay outside the kit.

> Acme paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the affidavit / GeoPath boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
- `SKILL.md` if you also run drive-by photos — it has the brand/policy recipe so you do not flip geofencing off for roadside stops
