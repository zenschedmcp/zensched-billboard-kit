# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first flight of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **Sightline Audits**, Dallas, Texas, Central time (`-05:00` in September). One campaign (Acme Coffee Iced, posting + mid-flight on two faces), one auditor, then invoice.

Access notes (shoulder pull-off, curb cut) and auditor pay handles stay in SQLite. They are never sent to ZenSched.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Billboard Audit Co, timezone_offset = -05:00,
    default_worker_id = NULL, invoice_due_days = 30, invoice_prefix = INV,
    default_visit_minutes = 15, default_checkin_radius_m = 200,
    proof_record_form_id = NULL, event_window_days = 60
```

## "My business is Sightline Audits in Dallas, Texas, Central time. Set the check-in radius to 200 m and create the Proof Record."

```
sqlite_execute: UPDATE settings SET value = 'Sightline Audits' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
sqlite_execute: UPDATE settings SET value = '200' WHERE key = 'default_checkin_radius_m';

policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 200, "checkin_reminder_min_before": 30}'
```

The radius is on the **policy**, not on any face.

```
form_create:
  title: "Proof Record"
  idempotency_key: "form-proof-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Proof record", "identifier": "sec_proof",
   "text": "Photograph the face so the creative is readable. This is an internal posting-proof record, not a legal affidavit, not Geopath / MRC measurement, not Veridooh / Seedooh / Broadsign proof-of-play, and not the media owner's official PoP certificate."},
  {"type": "photo", "label": "Creative up", "identifier": "creative_up", "required": true, "max_images": 2},
  {"type": "select", "label": "Matches brief", "identifier": "matches_brief", "required": true,
   "options": ["Yes", "No", "Partial"]},
  {"type": "textarea", "label": "Damage", "identifier": "damage"}
]
```

```
  → form_id: 501, fields: [ ...4 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'proof_record_form_id';
```

> Saved Sightline Audits in Central time (-05:00 in September; I will flip Dallas faces to `-06:00` after the first Sunday of November). Check-in radius is 200 m on the account policy (highway pull-offs); I will not set a radius "on a location." Proof Record created: creative photo up to 2, matches brief Yes / No / Partial, damage notes. No signature — this is an internal posting-proof, not an affidavit, not Geopath / MRC, not Veridooh / Broadsign proof-of-play, and not the plant's official PoP certificate.

## "New campaign. Advertiser Acme Coffee, contact Priya Nair, priya@acme.example, billing ap@acme.example, net 30. Creative: Acme Iced cup on black. Sep 8 through Oct 5, any day 7 to 7, posting plus mid-flight. $40 a visit to them, auditors get $20. Faces: SL-DAL-1102 N, bulletin, I-35N at Commerce St, Dallas TX 75202, dusk to dawn, shoulder pull-off southbound / SL-DAL-880 A, street furniture, Elm and Griffin, Dallas TX 75201, curb cut on Elm."

```
sqlite_execute:
  INSERT INTO campaigns (campaign_name, advertiser_name, contact_name, contact_email,
                         billing_email, payment_terms_days, flight_start, flight_end,
                         window_start_time, window_end_time, allowed_weekdays,
                         quota_per_face, client_fee, auditor_fee, min_minutes,
                         creative_name, creative_brief, auditor_brief, status)
  VALUES ('Acme Coffee Iced - Sep', 'Acme Coffee', 'Priya Nair', 'priya@acme.example',
          'ap@acme.example', 30, '2026-09-08', '2026-10-05',
          '07:00', '19:00', '1111111',
          2, 40.00, 20.00, 5,
          'Acme Iced',
          'Acme Iced cup on black. Whole face readable.',
          'Photograph the whole face so the cup is readable. Note tears, dark panels, graffiti, or a dark digital.',
          'draft');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO faces (plant_code, face_code, media_type, address, city, region, postal,
                     normalized_key, tz_offset, face_label, illumination, access_notes)
  VALUES ('SL-DAL-1102', 'N', 'bulletin', 'I-35N at Commerce St', 'Dallas', 'TX', '75202',
          'sl-dal-1102 n dallas tx', '-05:00', 'SL-DAL-1102 N', 'dusk to dawn',
          'Shoulder pull-off southbound. Do not stop in the travel lane.');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO faces (plant_code, face_code, media_type, address, city, region, postal,
                     normalized_key, tz_offset, face_label, illumination, access_notes)
  VALUES ('SL-DAL-880', 'A', 'street_furniture', 'Elm and Griffin', 'Dallas', 'TX', '75201',
          'sl-dal-880 a dallas tx', '-05:00', 'SL-DAL-880 A', 'none',
          'Curb cut on Elm. Shelter panel A faces west.');
  → lastInsertRowid = 2

sqlite_execute: INSERT INTO campaign_faces (campaign_id, face_id, visits_required) VALUES (1, 1, 2);
  → lastInsertRowid = 1
sqlite_execute: INSERT INTO campaign_faces (campaign_id, face_id, visits_required) VALUES (1, 2, 2);
  → lastInsertRowid = 2
```

Agent (first metered call this session, rule 10):

> Two new faces to geocode is $0.06. The 4 visits will be about $1.40 later ($0.35 each: two GPS punches + the photo record). If the account is not funded yet you will see the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "SL-DAL-1102 N"
  street_address: "I-35N at Commerce St, Dallas, TX 75202"
  checkin_radius_m: 200
  idempotency_key: "loc-face-1"
  → location_id: 9301, lat: 32.7767, lng: -96.7970, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }

location_create:
  name: "SL-DAL-880 A"
  street_address: "Elm and Griffin, Dallas, TX 75201"
  checkin_radius_m: 200
  idempotency_key: "loc-face-2"
  → location_id: 9302

sqlite_execute: UPDATE faces SET zensched_location_id = 9301 WHERE face_id = 1;
sqlite_execute: UPDATE faces SET zensched_location_id = 9302 WHERE face_id = 2;
```

The shoulder / curb notes are **not** in `notes`. They live only in `faces.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

```
event_create:
  location_id: 9301
  title: "Acme Iced - SL-DAL-1102 N"
  start_date: "2026-09-08"
  end_date:   "2026-10-05"          ← 27 days, under the 60-day cap
  idempotency_key: "event-cf-1-20260908"
  → event_id: 8101

form_assign:
  form_id: 501
  event_id: 8101
  idempotency_key: "assign-proof-record-8101"
  → status: "assigned", form_id: 501, event_id: 8101, policy_id: 0

event_create:
  location_id: 9302
  title: "Acme Iced - SL-DAL-880 A"
  start_date: "2026-09-08"
  end_date:   "2026-10-05"
  idempotency_key: "event-cf-2-20260908"
  → event_id: 8102

form_assign: form_id 501, event_id 8102, idempotency_key "assign-proof-record-8102"

sqlite_execute: UPDATE campaign_faces SET zensched_event_id = 8101, event_valid_until = '2026-10-05' WHERE campaign_face_id = 1;
sqlite_execute: UPDATE campaign_faces SET zensched_event_id = 8102, event_valid_until = '2026-10-05' WHERE campaign_face_id = 2;

sqlite_execute: INSERT INTO visits (campaign_face_id, visit_kind) VALUES (1, 'posting');
sqlite_execute: INSERT INTO visits (campaign_face_id, visit_kind) VALUES (1, 'mid_flight');
sqlite_execute: INSERT INTO visits (campaign_face_id, visit_kind) VALUES (2, 'posting');
sqlite_execute: INSERT INTO visits (campaign_face_id, visit_kind) VALUES (2, 'mid_flight');

sqlite_execute: UPDATE campaigns SET status = 'active' WHERE campaign_id = 1;
```

> Acme Coffee Iced - Sep: 2 faces, 4 visits (posting + mid-flight), every day 07:00–19:00 through Oct 5, $40 to Acme / $20 to the auditor. Proof Record is on both events. Shoulder and curb notes are on your computer only. Ready to assign.

## "Invite Jordan Hale, jordan@example.com, Dallas, PayPal same email, and make them the default."

> Inviting an auditor costs $0.25. OK?

Owner: *"yes"*

```
worker_invite:
  email: "jordan@example.com"
  first_name: "Jordan"
  last_name: "Hale"
  idempotency_key: "worker-jordan@example.com"
  → worker_id: 701, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO auditors (auditor_name, email, home_city, zensched_worker_id, pay_handle)
  VALUES ('Jordan Hale', 'jordan@example.com', 'Dallas', 701, 'jordan@example.com');
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '701' WHERE key = 'default_worker_id';
```

> Invited Jordan. They'll get an email with the app link and an activation code. They're the default auditor now. Pass the I-35 shoulder note and the Elm curb cut yourself; I keep those off ZenSched.

## "Give Jordan the two Dallas posting visits Thursday morning."

```
sqlite_query: SELECT * FROM visits_open WHERE city = 'Dallas' AND visit_kind = 'posting';
  → visit 1 | posting | SL-DAL-1102 N | evt 8101 | tz -05:00 | 07:00–19:00 | days_until_flight_end 27
    visit 3 | posting | SL-DAL-880 A  | evt 8102 | tz -05:00 | 07:00–19:00 | days_until_flight_end 27

sqlite_execute:
  UPDATE visits SET auditor_id = 1, scheduled_start = '2026-09-10T09:00:00',
                    scheduled_end = '2026-09-10T09:15:00', status = 'assigned'
  WHERE visit_id = 1;
sqlite_execute:
  UPDATE visits SET auditor_id = 1, scheduled_start = '2026-09-10T09:30:00',
                    scheduled_end = '2026-09-10T09:45:00', status = 'assigned'
  WHERE visit_id = 3;

sqlite_query: SELECT * FROM visits_upcoming WHERE zensched_shift_id IS NULL;
  → visit 1 | start_iso 2026-09-10T09:00:00-05:00 | end_iso 2026-09-10T09:15:00-05:00
             | idempotency_key shift-visit-1 | worker 701 | needs_location 0 | needs_event 0
    visit 3 | start_iso 2026-09-10T09:30:00-05:00 | end_iso 2026-09-10T09:45:00-05:00
             | shift-visit-3 | worker 701 | needs_location 0 | needs_event 0

shift_create:
  event_id: 8101
  worker_id: 701
  start: "2026-09-10T09:00:00-05:00"
  end:   "2026-09-10T09:15:00-05:00"
  idempotency_key: "shift-visit-1"
  → shift_id: 99011, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 8102
  worker_id: 701
  start: "2026-09-10T09:30:00-05:00"
  end:   "2026-09-10T09:45:00-05:00"
  idempotency_key: "shift-visit-3"
  → shift_id: 99013, status: "scheduled", forms_installed: [501]

sqlite_execute: UPDATE visits SET zensched_shift_id = 99011, zensched_worker_id = 701 WHERE visit_id = 1;
sqlite_execute: UPDATE visits SET zensched_shift_id = 99013, zensched_worker_id = 701 WHERE visit_id = 3;
```

> Assigned Jordan two Acme posting proofs Thursday:
> - 09:00–09:15  SL-DAL-1102 N  I-35N @ Commerce (bulletin)
> - 09:30–09:45  SL-DAL-880 A   Elm & Griffin (shelter)
>
> Notified in the app; Proof Record is on the phone. Each visit is about $0.35 once they punch and you read the photo record. Pass the shoulder / curb notes yourself. Two mid-flight visits are still open for the week of Sep 22.

Nothing else is written to SQLite for the live schedule. Asking again is safe: identical idempotency keys return the same shifts.

## Jordan does the work

Thursday 08:58, southbound shoulder at I-35N @ Commerce, in the ZenSched app: **Check in** (GPS: 22 m from the pin, verified, $0.10). Photographs the bulletin (cup readable, no tears). Opens **Proof Record**: Creative up = 2 photos; Matches brief = Yes; Damage blank. Submits (no signature). **Check out** 09:11 ($0.10).

Thursday 09:28, Elm & Griffin shelter: check in at the curb cut. Proof Record: Creative up = 2 photos; Matches brief = Partial; Damage = "Lower third still last-flight vinyl (previous QSR). Upper two-thirds Acme Iced." Check out 09:41.

## "Pull this week's proofs."

```
shift_list:
  date_from: "2026-09-08"
  date_to:   "2026-09-14"
  status:    "checked_out"
  → shifts: [
      { shift_id: 99011, event_id: 8101, worker_id: 701, date: "2026-09-10", start: "09:00", end: "09:15", status: "checked_out" },
      { shift_id: 99013, event_id: 8102, worker_id: 701, date: "2026-09-10", start: "09:30", end: "09:45", status: "checked_out" }
    ], count: 2
```

Agent (metered read, rule 10):

> Two Proof Records with photos, about $0.30. I'll read them once and keep the summaries locally. OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-08"
  until: "2026-09-14"
  format: "json"
  → row_count: 2, rows: [
      { submission_id: 5501, worker_id: 701, event_id: 8101, submitted_at: "2026-09-10 09:09:40",
        data: { matches_brief: "yes", damage: "" },
        media: [ { field_id: 12, cdn_url: "https://cdn.zensched.com/m/.../b1.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../b1_t.jpg", original_filename: "b1.jpg" },
                 { field_id: 12, cdn_url: "https://cdn.zensched.com/m/.../b2.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../b2_t.jpg", original_filename: "b2.jpg" } ] },
      { submission_id: 5502, worker_id: 701, event_id: 8102, submitted_at: "2026-09-10 09:39:12",
        data: { matches_brief: "partial",
                damage: "Lower third still last-flight vinyl (previous QSR). Upper two-thirds Acme Iced." },
        media: [ { field_id: 12, cdn_url: "https://cdn.zensched.com/m/.../s1.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../s1_t.jpg", original_filename: "s1.jpg" },
                 { field_id: 12, cdn_url: "https://cdn.zensched.com/m/.../s2.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../s2_t.jpg", original_filename: "s2.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 2, price: 0.30 }

shift_status: shift_id 99011
  → status "checked_out", actual_in "2026-09-10T08:58:20-05:00", actual_out "2026-09-10T09:11:05-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 22 },
               { type: "out", gps_verified: true, distance_from_site_m: 18 } ]

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 5501,
                    checkin_at = '2026-09-10T08:58:20-05:00', checkout_at = '2026-09-10T09:11:05-05:00',
                    gps_verified = 1, zensched_worker_id = 701,
                    matches_brief = 'Yes', damage = '',
                    photo_urls = '["https://cdn.zensched.com/m/.../b1.jpg","https://cdn.zensched.com/m/.../b2.jpg"]',
                    qa_status = 'pending'
  WHERE visit_id = 1;
  -- trigger: duration_minutes → 13

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 5502,
                    checkin_at = '2026-09-10T09:28:10-05:00', checkout_at = '2026-09-10T09:41:02-05:00',
                    gps_verified = 1, zensched_worker_id = 701,
                    matches_brief = 'Partial',
                    damage = 'Lower third still last-flight vinyl (previous QSR). Upper two-thirds Acme Iced.',
                    photo_urls = '["https://cdn.zensched.com/m/.../s1.jpg","https://cdn.zensched.com/m/.../s2.jpg"]',
                    qa_status = 'pending'
  WHERE visit_id = 3;
```

```
sqlite_query: SELECT * FROM visits_flagged WHERE qa_status = 'pending';
  → visit 3 | SL-DAL-880 A | matches_brief Partial | has_damage 1 | mismatch 1
    (visit 1 does not appear — Yes, no damage, on time)
```

> Pulled 2 visits, both GPS-verified.
>
> **Mismatch — SL-DAL-880 A (Elm & Griffin shelter):** Jordan marked **Partial** and noted damage: *"Lower third still last-flight vinyl (previous QSR). Upper two-thirds Acme Iced."* 2 photos.
>
> SL-DAL-1102 N (I-35 bulletin): matches brief Yes, no damage, 13 minutes on site, 22 m from the pin.
>
> This is your copy of the Proof Record, not an affidavit, not Geopath / MRC, not Veridooh / Broadsign proof-of-play, and not the plant's official PoP. Want me to approve the bulletin and reopen the shelter as a make-good?

## "Approve the I-35 bulletin. The shelter is Partial — reopen it as a make-good."

```
sqlite_execute: UPDATE visits SET qa_status = 'approved', qa_notes = 'Posting proof OK' WHERE visit_id = 1;
sqlite_execute: UPDATE visits SET qa_status = 'rejected', status = 'rejected',
                                qa_notes = 'Partial: last-flight vinyl on lower third; buyer wants make-good'
                WHERE visit_id = 3;
sqlite_execute: INSERT INTO visits (campaign_face_id, visit_kind) VALUES (2, 'make_good');
  → lastInsertRowid = 5
```

> Approved the I-35 bulletin. Rejected the shelter posting (stays on Jordan's history) and opened a make-good on SL-DAL-880 A. Say when to assign it.

## "What's wrong on Acme? Then invoice them and run auditor pay."

```
sqlite_query: SELECT * FROM proof_exceptions WHERE campaign_name LIKE '%Acme%';
  → visit 3 | 2026-09-10 | SL-DAL-880 A | Partial | Lower third still last-flight vinyl... | rejected

sqlite_query: SELECT * FROM visits_to_invoice;
  → campaign 1 | Acme Coffee Iced - Sep | 1 visit | 40.00

sqlite_execute:
  INSERT INTO invoices (campaign_id, advertiser_name, billing_email, invoice_date, due_date,
                        visit_count, fees_amount, total_amount, line_items)
  SELECT c.campaign_id, c.advertiser_name, c.billing_email, date('now'),
         date('now', '+' || COALESCE(c.payment_terms_days, 30) || ' days'),
         COUNT(*), SUM(c.client_fee), SUM(c.client_fee),
         json_group_array(json_object('visit_id', v.visit_id, 'date', date(v.scheduled_start),
                                      'face', f.face_label, 'kind', v.visit_kind,
                                      'matches', v.matches_brief, 'fee', c.client_fee))
  FROM visits v
  JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
  JOIN campaigns c ON c.campaign_id = cf.campaign_id
  JOIN faces f ON f.face_id = cf.face_id
  WHERE v.status = 'completed' AND v.qa_status = 'approved' AND v.client_invoiced = 0
    AND c.campaign_id = 1
  GROUP BY c.campaign_id;

sqlite_execute: UPDATE visits SET client_invoiced = 1 WHERE visit_id = 1;
sqlite_query:   SELECT invoice_number, due_date, visit_count, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-10-08 | 1 | 40.00

sqlite_query: SELECT * FROM auditor_pay_due;
  → Jordan Hale | jordan@example.com | 1 visit | 20.00 | [1]

sqlite_execute:
  INSERT INTO auditor_payouts (auditor_id, period_start, period_end, visit_count,
                               fees_amount, total_amount, visit_ids)
  VALUES (1, '2026-09-08', '2026-09-14', 1, 20.00, 20.00, '[1]');
sqlite_execute: UPDATE visits SET auditor_paid = 1 WHERE visit_id = 1;
```

> **Exceptions on Acme:** only the Elm & Griffin shelter (Sep 10, Partial, last-flight vinyl on the lower third). The I-35 bulletin matched.
>
> ```
> Sightline Audits
> Invoice INV-2026-0001
> To: Acme Coffee (ap@acme.example)
> Campaign: Acme Coffee Iced - Sep
> Date: Sep 10, 2026    Due: Oct 8, 2026
>
>   Sep 10    SL-DAL-1102 N    posting    $40.00
>
> Total due: $40.00
> Visit GPS-verified at the face with timestamped creative photos.
> This is posting proof, not a legal affidavit, not Geopath / MRC measurement, not Veridooh / Seedooh / Broadsign proof-of-play, and not the media owner's official PoP certificate.
> ```
>
> Jordan pay sheet: 1 approved visit, $20.00, PayPal jordan@example.com. Say "sent" and "Jordan paid" when those are done. Shelter make-good is still open.

## "Sent. Acme paid. Jordan paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now'), paid = 1, paid_date = date('now')
                WHERE invoice_number = 'INV-2026-0001';
sqlite_execute: UPDATE auditor_payouts SET paid = 1, paid_date = date('now') WHERE payout_id = 1;
```

> INV-2026-0001 marked sent and paid. Jordan's $20 marked paid.

## A 90-day booking: "Add a Q4 flight Sep 8 through Dec 6."

The schema rejects `flight_end` more than 59 days after `flight_start`. The agent splits:

```
-- window 1: 2026-09-08 .. 2026-11-06  (59 days)  Dallas still -05:00 through Nov 1
-- window 2: 2026-11-07 .. 2026-12-06            US Central DST ended 2026-11-01 → -06:00
```

Two `campaigns` rows, two sets of `campaign_faces` events (new `campaign_face_id`s, so `event-cf-{id}-{YYYYMMDD}` does not collide with window 1), same `faces` cache (no second geocode). Before assigning any visit on or after Nov 2, update Dallas faces:

```
sqlite_execute: UPDATE faces SET tz_offset = '-06:00' WHERE city = 'Dallas';
sqlite_execute: UPDATE settings SET value = '-06:00' WHERE key = 'timezone_offset';
```

India / Gulf / most LATAM faces skip this. November `shift_create` then uses `2026-11-09T09:00:00-06:00`, not the September `-05:00`.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Acme contact, $40 / $20 fees, flight dates, quota | SQLite | CRM; ZenSched does not model rates or flights |
| Shoulder pull-off, curb cut, PayPal handle | SQLite **only** | Privacy; never sent to ZenSched |
| Each face's GPS location | ZenSched (integer ID in `faces`) | Needed for geofenced check-in |
| Each face's ≤60-day event for this flight | ZenSched (integer ID + `event_valid_until` in `campaign_faces`) | Shifts hang off events |
| The Proof Record form | ZenSched (ID in `settings`) | Installed on the auditor's phone per shift |
| Jordan, the invite, the app | ZenSched (integer ID in `auditors`) | Workforce and notifications |
| The week's two shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` |
| Two Proof Records with photos | ZenSched (originals); summary + photo URLs in `visits` | Read once (metered), then exceptions / invoices from SQLite |
| Visit rows, one invoice, one payout | SQLite | Billing + proof extract |
