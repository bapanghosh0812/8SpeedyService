-- 8SpeedyService schema v1
-- All money is stored as integer paise. All timestamps are timestamptz (UTC).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid  TEXT NOT NULL UNIQUE,
  phone         TEXT NOT NULL UNIQUE,
  name          TEXT,
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'blocked', 'deleted')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE partners (
  user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  shop_name      TEXT NOT NULL,
  vehicle_types  TEXT[] NOT NULL,
  upi_id         TEXT,
  status         TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')),
  is_online      BOOLEAN NOT NULL DEFAULT false,
  lat            DOUBLE PRECISION,
  lng            DOUBLE PRECISION,
  location_at    TIMESTAMPTZ,
  rating_sum     INTEGER NOT NULL DEFAULT 0,
  rating_count   INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (cardinality(vehicle_types) > 0)
);

-- Only online + approved partners are ever scanned by dispatch.
CREATE INDEX partners_dispatch_idx ON partners (lat, lng)
  WHERE is_online AND status = 'approved';

CREATE TABLE partner_documents (
  partner_id    UUID NOT NULL REFERENCES partners(user_id) ON DELETE CASCADE,
  kind          TEXT NOT NULL CHECK (kind IN ('id_proof', 'selfie', 'shop_photo')),
  storage_path  TEXT NOT NULL,
  content_type  TEXT NOT NULL,
  size_bytes    INTEGER NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (partner_id, kind)
);

CREATE TABLE device_tokens (
  token       TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  app         TEXT NOT NULL CHECK (app IN ('customer', 'partner')),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX device_tokens_user_idx ON device_tokens (user_id, app);

CREATE TABLE bookings (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code               TEXT NOT NULL UNIQUE,
  customer_id        UUID NOT NULL REFERENCES users(id),
  partner_id         UUID REFERENCES partners(user_id),
  vehicle_type       TEXT NOT NULL,
  issue              TEXT NOT NULL,
  note               TEXT,
  vehicle_number     TEXT,
  lat                DOUBLE PRECISION NOT NULL,
  lng                DOUBLE PRECISION NOT NULL,
  address            TEXT,
  status             TEXT NOT NULL CHECK (status IN
                     ('searching', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled', 'expired')),
  visit_fee_paise    INTEGER NOT NULL CHECK (visit_fee_paise >= 0),
  extra_paise        INTEGER NOT NULL DEFAULT 0 CHECK (extra_paise >= 0),
  commission_paise   INTEGER,
  payment_method     TEXT CHECK (payment_method IN ('cash', 'upi')),
  start_otp          TEXT NOT NULL,
  otp_attempts       INTEGER NOT NULL DEFAULT 0,
  dispatch_wave      INTEGER NOT NULL DEFAULT 0,
  next_dispatch_at   TIMESTAMPTZ,
  cancel_reason      TEXT,
  cancelled_by       TEXT CHECK (cancelled_by IN ('customer', 'partner', 'system')),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at        TIMESTAMPTZ,
  arrived_at         TIMESTAMPTZ,
  started_at         TIMESTAMPTZ,
  completed_at       TIMESTAMPTZ,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Hard guarantees enforced by the database itself, not just application code:
-- a customer can have only one live booking, a partner only one live job.
CREATE UNIQUE INDEX bookings_one_live_per_customer ON bookings (customer_id)
  WHERE status IN ('searching', 'accepted', 'arrived', 'in_progress');
CREATE UNIQUE INDEX bookings_one_live_per_partner ON bookings (partner_id)
  WHERE status IN ('accepted', 'arrived', 'in_progress');
CREATE INDEX bookings_dispatch_due_idx ON bookings (next_dispatch_at) WHERE status = 'searching';
CREATE INDEX bookings_customer_idx ON bookings (customer_id, created_at DESC);
CREATE INDEX bookings_partner_idx ON bookings (partner_id, created_at DESC);

CREATE TABLE booking_offers (
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  partner_id  UUID NOT NULL REFERENCES partners(user_id) ON DELETE CASCADE,
  wave        INTEGER NOT NULL,
  distance_m  INTEGER NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'lost')),
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (booking_id, partner_id)
);
CREATE INDEX booking_offers_partner_idx ON booking_offers (partner_id, status);

CREATE TABLE booking_charges (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id    UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  description   TEXT NOT NULL,
  amount_paise  INTEGER NOT NULL CHECK (amount_paise > 0),
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at    TIMESTAMPTZ
);
CREATE INDEX booking_charges_booking_idx ON booking_charges (booking_id);

CREATE TABLE booking_events (
  id          BIGSERIAL PRIMARY KEY,
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,
  actor_id    UUID,
  data        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX booking_events_booking_idx ON booking_events (booking_id, id);

CREATE TABLE ratings (
  booking_id  UUID PRIMARY KEY REFERENCES bookings(id) ON DELETE CASCADE,
  stars       SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Append-only money ledger. Corrections are new rows, never edits.
CREATE TABLE ledger_entries (
  id            BIGSERIAL PRIMARY KEY,
  partner_id    UUID NOT NULL REFERENCES partners(user_id),
  booking_id    UUID REFERENCES bookings(id),
  type          TEXT NOT NULL CHECK (type IN ('commission_due', 'commission_paid', 'adjustment')),
  amount_paise  INTEGER NOT NULL,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ledger_one_commission_per_booking ON ledger_entries (booking_id)
  WHERE type = 'commission_due';
CREATE INDEX ledger_partner_idx ON ledger_entries (partner_id, id DESC);

CREATE FUNCTION ledger_block_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'ledger_entries is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ledger_no_update BEFORE UPDATE ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION ledger_block_mutation();
CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION ledger_block_mutation();

CREATE TABLE idempotency_keys (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key         TEXT NOT NULL,
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);

-- Used by @socket.io/postgres-adapter when running more than one API instance.
CREATE TABLE IF NOT EXISTS socket_io_attachments (
  id          BIGSERIAL UNIQUE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  payload     BYTEA
);
