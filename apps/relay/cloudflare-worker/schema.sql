CREATE TABLE IF NOT EXISTS diagnostic_reports (
  id TEXT PRIMARY KEY NOT NULL,
  received_at TEXT NOT NULL,
  repository TEXT,
  report_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS diagnostic_reports_received_at
  ON diagnostic_reports (received_at);
