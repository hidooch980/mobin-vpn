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
