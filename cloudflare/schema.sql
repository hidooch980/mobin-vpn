-- MolidoVPN anonymous connection reports (aggregated per day; no IPs, no per-request rows).
CREATE TABLE IF NOT EXISTS reports (
  day TEXT NOT NULL,
  node TEXT NOT NULL,
  app TEXT NOT NULL,
  net TEXT NOT NULL,
  ok INTEGER NOT NULL DEFAULT 0,
  fail INTEGER NOT NULL DEFAULT 0,
  ms_sum INTEGER NOT NULL DEFAULT 0,
  ms_n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, node, app, net)
);

-- Owner-added subscription links and configs (managed from /admin). Also created lazily by the worker.
CREATE TABLE IF NOT EXISTS owner_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('sub', 'config')),
  value TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  always_show INTEGER NOT NULL DEFAULT 0, -- serve even if the local Iran test fails
  due_at INTEGER NOT NULL DEFAULT 0       -- "test again" pressed (ms); quick local test picks it up
);

-- Latest local Iran test per owner config fingerprint (iran_node_test.py, uploaded via /report with owner:true).
CREATE TABLE IF NOT EXISTS owner_tests (
  fp TEXT PRIMARY KEY,
  ok INTEGER NOT NULL,
  ms INTEGER,
  tested_at INTEGER NOT NULL,
  fail_streak INTEGER NOT NULL DEFAULT 0
);

-- Failed admin logins per salted IP hash (lockout); rows removed after one day.
CREATE TABLE IF NOT EXISTS admin_fails (
  ip_hash TEXT PRIMARY KEY,
  fails INTEGER NOT NULL,
  locked_until INTEGER NOT NULL,
  updated INTEGER NOT NULL
);
