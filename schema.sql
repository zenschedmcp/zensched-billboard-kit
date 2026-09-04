-- ZenSched Billboard / Street-Furniture Photo-Audit Local Database Schema
-- SQLite database for campaigns (flights), faces (places), audit visits,
-- Proof Record summaries, auditor pay, and client invoicing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, the
-- original form submissions and creative photos).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my billboard database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 billboard.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- WHAT CROSSES TO ZENSCHED AND WHAT DOES NOT
--   ZenSched receives: a face label (plant + face, e.g. 'SL-DAL-1102 N'),
--   the face's street / nearest-intersection address for the GPS pin, an
--   event title per face per campaign (the creative name may appear:
--   auditors must know what should be on the board), the Proof Record
--   form, and the auditor's account (name + email).
--   ZenSched never receives: advertiser billing contacts, fees, auditor
--   pay handles, access notes (shoulder / parking / ladder), QA notes, or
--   plant access codes. Those live only here. SKILL.md makes this a hard rule.
--
-- NOT A LEGAL AFFIDAVIT. The Proof Record is an internal posting-proof
-- (photo + matches-brief + damage). It is not a signed affidavit, not a
-- GeoPath / OAAA / Nielsen audit, and not a burned-in GPS stamp on the
-- image itself. Contract disputes still need whatever your counsel wants.
--
-- TIME CONVENTIONS
--   visits.scheduled_start / scheduled_end are FACE-LOCAL wall-clock times
--   without an offset ('2026-09-09T09:00:00'). Views append the face's
--   tz_offset to build the ISO strings shift_create needs.
--   visits.checkin_at / checkout_at are ISO 8601 WITH an explicit offset, as
--   recorded from ZenSched.
--
-- MODEL
--   campaigns → faces (places) → audit visits
--   faces are a place cache (one ZenSched LOCATION each, reused).
--   campaign_faces is the booking of a face onto a flight and holds the
--   ≤60-day ZenSched EVENT. visits hang off campaign_faces.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session.
-- timezone_offset is the DEFAULT for new faces; each face carries its own
-- tz_offset because a national campaign spans zones.
-- default_checkin_radius_m is informational: the radius ZenSched enforces is
-- the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Billboard Audit Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '15');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '200');
INSERT OR IGNORE INTO settings (key, value) VALUES ('proof_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');

-- Campaigns: one FLIGHT of posting-proof visits for one advertiser / buyer.
-- flight_end is at most 59 days after flight_start because a ZenSched event
-- is capped at 60 days and the kit creates one event per face per campaign
-- (the CHECK below enforces the split). A quarter-long booking is several
-- campaign rows. allowed_weekdays is a 7-character 0/1 mask, Monday first:
-- '1111100' = weekdays only.
CREATE TABLE IF NOT EXISTS campaigns (
  campaign_id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_name TEXT NOT NULL,                      -- 'Acme Coffee Iced - Sep'
  advertiser_name TEXT NOT NULL,
  contact_name TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER DEFAULT 30,
  flight_start TEXT NOT NULL,                       -- ISO date
  flight_end TEXT NOT NULL                          -- ISO date, at most 59 days after flight_start
    CHECK (flight_end >= flight_start AND julianday(flight_end) - julianday(flight_start) <= 59),
  window_start_time TEXT NOT NULL DEFAULT '07:00'   -- earliest local time a visit may start
    CHECK (window_start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  window_end_time TEXT NOT NULL DEFAULT '19:00'     -- latest local time a visit may END
    CHECK (window_end_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  allowed_weekdays TEXT NOT NULL DEFAULT '1111111'
    CHECK (length(allowed_weekdays) = 7 AND allowed_weekdays NOT GLOB '*[^01]*'),
  quota_per_face INTEGER NOT NULL DEFAULT 1 CHECK (quota_per_face >= 1),
  client_fee REAL NOT NULL,                         -- what the buyer pays per approved visit
  auditor_fee REAL NOT NULL,                        -- what the auditor earns per approved visit
  min_minutes INTEGER DEFAULT 5,                    -- visits shorter than this are flagged
  creative_name TEXT,                               -- short name that MAY appear on the event title
  creative_brief TEXT,                              -- LOCAL: what should be on the face
  auditor_brief TEXT,                               -- the ONLY operational text an auditor may be told
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'active', 'closed')),
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Faces: the cache of physical places (one billboard face, one shelter panel,
-- one transit unit). One ZenSched LOCATION each, created once and kept
-- forever (geocoding is metered). Keyed by normalized_key so the same plant
-- pasted on two campaigns is one row and one geocode.
-- tz_offset is PER FACE. face_label is the only name that crosses to ZenSched.
-- access_notes are LOCAL ONLY (highway shoulder, lot, ladder, gate).
CREATE TABLE IF NOT EXISTS faces (
  face_id INTEGER PRIMARY KEY AUTOINCREMENT,
  plant_code TEXT,                                  -- operator plant id, e.g. 'SL-DAL-1102'
  face_code TEXT,                                   -- 'N', 'S', 'A', 'digital-1'
  media_type TEXT NOT NULL DEFAULT 'bulletin'
    CHECK (media_type IN ('bulletin', 'poster', 'digital', 'street_furniture', 'transit', 'other')),
  address TEXT NOT NULL,                            -- street or nearest intersection
  city TEXT,
  region TEXT,                                      -- state / province
  country TEXT DEFAULT 'US',
  postal TEXT,
  normalized_key TEXT NOT NULL UNIQUE,              -- see SKILL.md "Normalize a face"
  tz_offset TEXT NOT NULL                           -- '-05:00'; defaults to settings.timezone_offset
    CHECK (tz_offset GLOB '[+-][0-1][0-9]:[0-5][0-9]'),
  face_label TEXT,                                  -- name sent to ZenSched: plant + face
  illumination TEXT,                                -- 'dusk to dawn', 'none', 'digital'
  access_notes TEXT,                                -- LOCAL ONLY: shoulder, parking, ladder, gate
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Campaign x face: which faces are on this flight, how many audit visits
-- each needs, and the ZenSched EVENT for that face for this campaign
-- (start_date = flight_start, end_date = flight_end, never more than 60 days).
-- The org's Proof Record form is assigned to the event so it installs on
-- the auditor's phone at shift_create.
CREATE TABLE IF NOT EXISTS campaign_faces (
  campaign_face_id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_id INTEGER NOT NULL,
  face_id INTEGER NOT NULL,
  visits_required INTEGER NOT NULL DEFAULT 1 CHECK (visits_required >= 0),
  zensched_event_id INTEGER,                        -- from event_create
  event_valid_until TEXT,                           -- ISO date: last day the event covers (= flight_end)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (campaign_id) REFERENCES campaigns(campaign_id) ON DELETE CASCADE,
  FOREIGN KEY (face_id) REFERENCES faces(face_id) ON DELETE CASCADE,
  UNIQUE (campaign_id, face_id)
);

-- Auditors: the contractor / in-house photo-auditor pool.
-- zensched_worker_id comes from worker_invite. pay_handle is LOCAL ONLY.
CREATE TABLE IF NOT EXISTS auditors (
  auditor_id INTEGER PRIMARY KEY AUTOINCREMENT,
  auditor_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  home_city TEXT,
  home_region TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  pay_handle TEXT,                                  -- LOCAL ONLY: how you pay them
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per audit visit the campaign requires. Created 'open' from
-- the quota, becomes 'assigned' when an auditor and a date/time slot are
-- chosen (one ZenSched shift), then 'completed' / 'no_show' / 'rejected' /
-- 'cancelled'. scheduled_* are face-local wall-clock; checkin_at / checkout_at
-- are ISO with offset from ZenSched. duration_minutes is filled by trigger
-- when left NULL. matches_brief / damage / photo_urls are the Proof Record
-- summary (labels, not option keys).
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_face_id INTEGER NOT NULL,
  auditor_id INTEGER,                               -- NULL until assigned
  visit_kind TEXT NOT NULL DEFAULT 'posting'
    CHECK (visit_kind IN ('posting', 'mid_flight', 'take_down', 'make_good', 'spot')),
  scheduled_start TEXT                              -- face-local, no offset
    CHECK (scheduled_start IS NULL OR scheduled_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
  scheduled_end TEXT
    CHECK (scheduled_end IS NULL OR scheduled_end GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
  zensched_shift_id INTEGER UNIQUE,                 -- from shift_create
  zensched_worker_id INTEGER,                       -- from shift_create / worker_invite
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'assigned', 'completed', 'no_show', 'rejected', 'cancelled')),
  submission_dc_id INTEGER,                         -- Proof Record submission_id
  checkin_at TEXT,                                  -- ISO with offset, from shift_status
  checkout_at TEXT,
  duration_minutes INTEGER,                         -- trigger fills from punches if NULL
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  matches_brief TEXT
    CHECK (matches_brief IS NULL OR matches_brief IN ('Yes', 'No', 'Partial')),
  damage TEXT,                                      -- as the auditor wrote it
  photo_urls TEXT,                                  -- JSON array of media URLs from the report
  qa_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (qa_status IN ('pending', 'approved', 'rejected')),
  qa_notes TEXT,                                    -- LOCAL ONLY
  client_invoiced INTEGER DEFAULT 0,
  auditor_paid INTEGER DEFAULT 0,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (campaign_face_id) REFERENCES campaign_faces(campaign_face_id) ON DELETE CASCADE,
  FOREIGN KEY (auditor_id) REFERENCES auditors(auditor_id) ON DELETE SET NULL
);

-- Invoices to buyers. invoice_number is filled by trigger if left NULL.
-- line_items is a JSON array with one object per visit.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_id INTEGER,                              -- NULL when one invoice spans campaigns
  advertiser_name TEXT NOT NULL,
  billing_email TEXT,
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  visit_count INTEGER,
  fees_amount REAL,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array: one object per visit
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (campaign_id) REFERENCES campaigns(campaign_id) ON DELETE SET NULL
);

-- Auditor payouts: one row per auditor per pay run. The shop pays outside
-- the kit (PayPal, Venmo, bank); this is the record.
CREATE TABLE IF NOT EXISTS auditor_payouts (
  payout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  auditor_id INTEGER NOT NULL,
  period_start TEXT,
  period_end TEXT,
  visit_count INTEGER,
  fees_amount REAL,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  visit_ids TEXT,                                   -- JSON array of visit_id
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (auditor_id) REFERENCES auditors(auditor_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status, flight_end);
CREATE INDEX IF NOT EXISTS idx_faces_normalized ON faces(normalized_key);
CREATE INDEX IF NOT EXISTS idx_faces_zensched_location ON faces(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_campaign_faces_campaign ON campaign_faces(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_faces_face ON campaign_faces(face_id);
CREATE INDEX IF NOT EXISTS idx_campaign_faces_event ON campaign_faces(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_visits_campaign_face ON visits(campaign_face_id, status);
CREATE INDEX IF NOT EXISTS idx_visits_auditor ON visits(auditor_id, status);
CREATE INDEX IF NOT EXISTS idx_visits_scheduled ON visits(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_visits_qa ON visits(qa_status, client_invoiced, auditor_paid);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);
CREATE INDEX IF NOT EXISTS idx_payouts_auditor ON auditor_payouts(auditor_id, paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_campaign_timestamp
AFTER UPDATE ON campaigns
BEGIN
  UPDATE campaigns SET updated_at = datetime('now') WHERE campaign_id = NEW.campaign_id;
END;

CREATE TRIGGER IF NOT EXISTS update_face_timestamp
AFTER UPDATE ON faces
BEGIN
  UPDATE faces SET updated_at = datetime('now') WHERE face_id = NEW.face_id;
END;

CREATE TRIGGER IF NOT EXISTS update_auditor_timestamp
AFTER UPDATE ON auditors
BEGIN
  UPDATE auditors SET updated_at = datetime('now') WHERE auditor_id = NEW.auditor_id;
END;

CREATE TRIGGER IF NOT EXISTS update_visit_timestamp
AFTER UPDATE ON visits
BEGIN
  UPDATE visits SET updated_at = datetime('now') WHERE visit_id = NEW.visit_id;
END;

-- Fill auditor_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_auditor
AFTER INSERT ON visits
WHEN NEW.auditor_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE visits
  SET auditor_id = (SELECT auditor_id FROM auditors WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Fill duration_minutes from the punches when the agent leaves it NULL, on
-- insert and whenever the punch columns change. Both stamps carry an offset,
-- so julianday arithmetic is exact even across midnight or time zones.
CREATE TRIGGER IF NOT EXISTS fill_visit_duration_insert
AFTER INSERT ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.checkout_at) - julianday(NEW.checkin_at)) * 1440.0) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

CREATE TRIGGER IF NOT EXISTS fill_visit_duration_update
AFTER UPDATE OF checkin_at, checkout_at ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.checkout_at) - julianday(NEW.checkin_at)) * 1440.0) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Unassigned visits in active campaigns, with everything the agent needs to
-- propose an assignment: face, city, tz, the daily window, allowed weekdays,
-- and how many days remain in the flight. Sorted by urgency.
CREATE VIEW IF NOT EXISTS visits_open AS
SELECT
  v.visit_id,
  v.visit_kind,
  c.campaign_id,
  c.campaign_name,
  c.advertiser_name,
  c.creative_name,
  c.auditor_brief,
  f.face_id,
  f.plant_code,
  f.face_code,
  f.media_type,
  f.address,
  f.city,
  f.region,
  f.tz_offset,
  f.face_label,
  f.access_notes,
  f.zensched_location_id,
  cf.campaign_face_id,
  cf.zensched_event_id,
  c.flight_start,
  c.flight_end,
  c.window_start_time,
  c.window_end_time,
  c.allowed_weekdays,
  c.min_minutes,
  c.auditor_fee,
  CAST(julianday(c.flight_end) - julianday(date('now')) AS INTEGER) AS days_until_flight_end
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
JOIN faces f           ON f.face_id = cf.face_id
WHERE v.status = 'open'
  AND c.status = 'active'
  AND cf.is_active = 1
ORDER BY c.flight_end, f.city, f.plant_code;

-- Assigned visits in the next 7 days (today + 6, by face-local date). One
-- row = one shift_create call (if zensched_shift_id is NULL) or one shift to
-- watch. start_iso / end_iso use the FACE's tz_offset. needs_location /
-- needs_event mean the face or the campaign-face row has not been set up on
-- ZenSched yet.
CREATE VIEW IF NOT EXISTS visits_upcoming AS
SELECT
  v.visit_id,
  v.status,
  v.visit_kind,
  c.campaign_id,
  c.campaign_name,
  c.advertiser_name,
  c.creative_name,
  c.auditor_brief,
  f.face_id,
  f.plant_code,
  f.face_code,
  f.address,
  f.city,
  f.tz_offset,
  f.face_label,
  f.access_notes,
  f.zensched_location_id,
  cf.campaign_face_id,
  cf.zensched_event_id,
  cf.event_valid_until,
  a.auditor_id,
  a.auditor_name,
  a.zensched_worker_id                               AS worker_id,
  v.scheduled_start,
  v.scheduled_end,
  v.scheduled_start || f.tz_offset                  AS start_iso,
  v.scheduled_end   || f.tz_offset                  AS end_iso,
  'shift-visit-' || v.visit_id                       AS idempotency_key,
  v.zensched_shift_id,
  CASE WHEN f.zensched_location_id IS NULL THEN 1 ELSE 0 END AS needs_location,
  CASE WHEN cf.zensched_event_id IS NULL
         OR cf.event_valid_until IS NULL
         OR cf.event_valid_until < date(v.scheduled_start) THEN 1 ELSE 0 END AS needs_event
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
JOIN faces f           ON f.face_id = cf.face_id
LEFT JOIN auditors a   ON a.auditor_id = v.auditor_id
WHERE v.status = 'assigned'
  AND date(v.scheduled_start) BETWEEN date('now') AND date('now', '+6 days')
ORDER BY v.scheduled_start, f.city;

-- Assigned visits whose slot has already ended (face-local, compared in UTC)
-- with no result recorded. Either the auditor did it and results have not
-- been pulled, or it is a no-show.
CREATE VIEW IF NOT EXISTS visits_overdue AS
SELECT
  v.visit_id,
  v.visit_kind,
  c.campaign_id,
  c.campaign_name,
  c.advertiser_name,
  f.face_label,
  f.address,
  f.city,
  f.tz_offset,
  cf.zensched_event_id,
  a.auditor_id,
  a.auditor_name,
  a.zensched_worker_id                               AS worker_id,
  v.scheduled_start,
  v.scheduled_end,
  v.zensched_shift_id,
  CAST((julianday('now') - julianday(v.scheduled_end || f.tz_offset)) * 24 AS INTEGER) AS hours_overdue
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
JOIN faces f           ON f.face_id = cf.face_id
LEFT JOIN auditors a   ON a.auditor_id = v.auditor_id
WHERE v.status = 'assigned'
  AND v.scheduled_end IS NOT NULL
  AND julianday(v.scheduled_end || f.tz_offset) < julianday('now')
ORDER BY v.scheduled_end;

-- Completed visits with a quality signal, for QA to look at first:
--   checkin_late     check-in after the assigned slot ended
--   checkin_early    check-in more than 15 minutes before the slot started
--   no_checkin       completed (form in) but no GPS check-in recorded
--   short_visit      duration below the campaign's min_minutes
--   mismatch         matches_brief is No or Partial
--   has_damage       damage text is non-empty
-- On-time visits that match the brief with no damage do not appear here.
CREATE VIEW IF NOT EXISTS visits_flagged AS
SELECT
  v.visit_id,
  v.visit_kind,
  c.campaign_id,
  c.campaign_name,
  c.advertiser_name,
  f.face_label,
  f.address,
  f.city,
  f.tz_offset,
  a.auditor_id,
  a.auditor_name,
  v.scheduled_start,
  v.scheduled_end,
  v.checkin_at,
  v.checkout_at,
  v.duration_minutes,
  c.min_minutes,
  v.matches_brief,
  v.damage,
  v.submission_dc_id,
  v.zensched_shift_id,
  v.qa_status,
  CASE WHEN v.checkin_at IS NOT NULL
        AND julianday(v.checkin_at) > julianday(v.scheduled_end || f.tz_offset) THEN 1 ELSE 0 END AS checkin_late,
  CASE WHEN v.checkin_at IS NOT NULL
        AND julianday(v.checkin_at) < julianday(v.scheduled_start || f.tz_offset, '-15 minutes') THEN 1 ELSE 0 END AS checkin_early,
  CASE WHEN v.checkin_at IS NULL THEN 1 ELSE 0 END AS no_checkin,
  CASE WHEN v.duration_minutes IS NOT NULL AND v.duration_minutes < COALESCE(c.min_minutes, 0) THEN 1 ELSE 0 END AS short_visit,
  CASE WHEN v.matches_brief IN ('No', 'Partial') THEN 1 ELSE 0 END AS mismatch,
  CASE WHEN v.damage IS NOT NULL AND trim(v.damage) <> '' THEN 1 ELSE 0 END AS has_damage,
  CAST(round((julianday(v.checkin_at) - julianday(v.scheduled_end || f.tz_offset)) * 1440.0) AS INTEGER) AS minutes_after_slot_end
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
JOIN faces f           ON f.face_id = cf.face_id
LEFT JOIN auditors a   ON a.auditor_id = v.auditor_id
WHERE v.status = 'completed'
  AND (
       v.checkin_at IS NULL
    OR julianday(v.checkin_at) > julianday(v.scheduled_end || f.tz_offset)
    OR julianday(v.checkin_at) < julianday(v.scheduled_start || f.tz_offset, '-15 minutes')
    OR (v.duration_minutes IS NOT NULL AND v.duration_minutes < COALESCE(c.min_minutes, 0))
    OR v.matches_brief IN ('No', 'Partial')
    OR (v.damage IS NOT NULL AND trim(v.damage) <> '')
  )
ORDER BY CASE v.qa_status WHEN 'pending' THEN 0 ELSE 1 END, v.scheduled_start;

-- One row per campaign: how many visits are required, assigned, completed,
-- approved, percent complete (approved / required), and days left in the flight.
CREATE VIEW IF NOT EXISTS campaign_progress AS
SELECT
  c.campaign_id,
  c.campaign_name,
  c.advertiser_name,
  c.status,
  c.flight_start,
  c.flight_end,
  CAST(julianday(c.flight_end) - julianday(date('now')) AS INTEGER)            AS days_left,
  (SELECT COUNT(*) FROM campaign_faces cf WHERE cf.campaign_id = c.campaign_id AND cf.is_active = 1) AS face_count,
  (SELECT COALESCE(SUM(cf.visits_required), 0) FROM campaign_faces cf WHERE cf.campaign_id = c.campaign_id AND cf.is_active = 1) AS visits_required,
  (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
     WHERE cf.campaign_id = c.campaign_id AND v.status = 'open')               AS visits_open,
  (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
     WHERE cf.campaign_id = c.campaign_id AND v.status = 'assigned')           AS visits_assigned,
  (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
     WHERE cf.campaign_id = c.campaign_id AND v.status = 'completed')          AS visits_completed,
  (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
     WHERE cf.campaign_id = c.campaign_id AND v.status = 'completed' AND v.qa_status = 'approved') AS visits_approved,
  (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
     WHERE cf.campaign_id = c.campaign_id AND v.status = 'no_show')            AS visits_no_show,
  (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
     WHERE cf.campaign_id = c.campaign_id AND v.status = 'completed' AND v.qa_status = 'pending') AS visits_qa_pending,
  CASE WHEN (SELECT COALESCE(SUM(cf.visits_required), 0) FROM campaign_faces cf WHERE cf.campaign_id = c.campaign_id AND cf.is_active = 1) = 0 THEN 0
       ELSE round(100.0 *
            (SELECT COUNT(*) FROM visits v JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
               WHERE cf.campaign_id = c.campaign_id AND v.status = 'completed' AND v.qa_status = 'approved')
            / (SELECT SUM(cf.visits_required) FROM campaign_faces cf WHERE cf.campaign_id = c.campaign_id AND cf.is_active = 1), 1)
  END AS pct_complete
FROM campaigns c
ORDER BY c.status = 'active' DESC, c.flight_end;

-- Approved visits not yet invoiced, grouped by campaign / advertiser.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.campaign_id,
  c.campaign_name,
  c.advertiser_name,
  c.billing_email,
  c.payment_terms_days,
  COUNT(v.visit_id)                                   AS visit_count,
  SUM(c.client_fee)                                   AS fees_amount,
  SUM(c.client_fee)                                   AS total_amount,
  MIN(date(v.scheduled_start))                        AS first_visit_date,
  MAX(date(v.scheduled_start))                        AS last_visit_date
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
WHERE v.status = 'completed'
  AND v.qa_status = 'approved'
  AND v.client_invoiced = 0
GROUP BY c.campaign_id
ORDER BY c.advertiser_name, c.campaign_name;

-- Approved visits not yet paid to the auditor, grouped by auditor.
CREATE VIEW IF NOT EXISTS auditor_pay_due AS
SELECT
  a.auditor_id,
  a.auditor_name,
  a.email,
  a.pay_handle,
  COUNT(v.visit_id)                                   AS visit_count,
  SUM(c.auditor_fee)                                  AS fees_amount,
  SUM(c.auditor_fee)                                  AS total_due,
  MIN(date(v.scheduled_start))                        AS first_visit_date,
  MAX(date(v.scheduled_start))                        AS last_visit_date,
  json_group_array(v.visit_id)                        AS visit_ids
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
JOIN auditors a        ON a.auditor_id = v.auditor_id
WHERE v.status = 'completed'
  AND v.qa_status = 'approved'
  AND v.auditor_paid = 0
GROUP BY a.auditor_id
ORDER BY a.auditor_name;

-- Per auditor: how many visits they were given, completed, no-showed,
-- had rejected, and what share of their visits (completed or rejected) had
-- an on-time check-in (within 15 minutes before the slot start and before
-- the slot end). Use this when deciding who gets the next assignment.
CREATE VIEW IF NOT EXISTS auditor_reliability AS
SELECT
  a.auditor_id,
  a.auditor_name,
  a.home_city,
  a.is_active,
  COUNT(v.visit_id) FILTER (WHERE v.status IN ('assigned', 'completed', 'no_show', 'rejected')) AS visits_given,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'completed')                                        AS completed,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'completed' AND v.qa_status = 'approved')           AS approved,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'no_show')                                          AS no_shows,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'rejected' OR (v.status = 'completed' AND v.qa_status = 'rejected')) AS rejected,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'assigned')                                         AS upcoming,
  CASE WHEN COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL) = 0 THEN NULL
       ELSE round(100.0 *
            COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL
                                        AND julianday(v.checkin_at) >= julianday(v.scheduled_start || f.tz_offset, '-15 minutes')
                                        AND julianday(v.checkin_at) <= julianday(v.scheduled_end || f.tz_offset))
            / COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL), 1)
  END AS on_time_pct,
  MAX(date(v.scheduled_start)) FILTER (WHERE v.status = 'completed')                             AS last_completed_date
FROM auditors a
LEFT JOIN visits v          ON v.auditor_id = a.auditor_id
LEFT JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
LEFT JOIN faces f           ON f.face_id = cf.face_id
GROUP BY a.auditor_id
ORDER BY a.is_active DESC, no_shows, a.auditor_name;

-- Unpaid buyer invoices with aging.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  i.advertiser_name,
  i.billing_email,
  i.invoice_date,
  i.due_date,
  i.visit_count,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue,
  CASE WHEN i.due_date >= date('now') THEN 0
       ELSE CAST(julianday(date('now')) - julianday(i.due_date) AS INTEGER) END AS days_overdue,
  CASE WHEN i.due_date >= date('now') THEN 'current'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 30 THEN '1-30'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 60 THEN '31-60'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 90 THEN '61-90'
       ELSE '90+' END AS aging_bucket
FROM invoices i
WHERE i.paid = 0
ORDER BY i.due_date;

-- Owner's local extract of posting problems: completed visits that did not
-- fully match the brief, or that noted damage. Answer "what's wrong on
-- Acme" from here, not by re-reading submissions.
CREATE VIEW IF NOT EXISTS proof_exceptions AS
SELECT
  v.visit_id,
  v.visit_kind,
  date(v.scheduled_start)                            AS visit_date,
  c.campaign_name,
  c.advertiser_name,
  c.creative_name,
  f.face_label,
  f.plant_code,
  f.face_code,
  f.address,
  f.city,
  COALESCE(a.auditor_name, 'auditor ' || v.auditor_id) AS auditor,
  v.matches_brief,
  v.damage,
  v.photo_urls,
  v.gps_verified,
  v.zensched_shift_id,
  v.submission_dc_id,
  v.qa_status
FROM visits v
JOIN campaign_faces cf ON cf.campaign_face_id = v.campaign_face_id
JOIN campaigns c       ON c.campaign_id = cf.campaign_id
JOIN faces f           ON f.face_id = cf.face_id
LEFT JOIN auditors a   ON a.auditor_id = v.auditor_id
WHERE v.status = 'completed'
  AND (
       v.matches_brief IN ('No', 'Partial')
    OR (v.damage IS NOT NULL AND trim(v.damage) <> '')
  )
ORDER BY visit_date DESC, c.campaign_name;
