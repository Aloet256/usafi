-- USAFI Balancing System - Supabase schema
-- Run this in Supabase SQL Editor before using usafi_app_improved.html.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.staff (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  email text NOT NULL UNIQUE,
  location text DEFAULT 'USAFI',
  role text NOT NULL DEFAULT 'staff' CHECK (role IN ('admin', 'staff', 'viewer')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.daily_balance_entries (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  location text NOT NULL DEFAULT 'USAFI',
  entry_date date NOT NULL,
  opening_balance numeric(15, 2) NOT NULL DEFAULT 0,
  normal_sales numeric(15, 2) NOT NULL DEFAULT 0,
  virtual_sales numeric(15, 2) NOT NULL DEFAULT 0,
  normal_payout numeric(15, 2) NOT NULL DEFAULT 0,
  virtual_payout numeric(15, 2) NOT NULL DEFAULT 0,
  cash_in numeric(15, 2) NOT NULL DEFAULT 0,
  cash_out numeric(15, 2) NOT NULL DEFAULT 0,
  cash_at_hand numeric(15, 2) NOT NULL DEFAULT 0,
  shortage_explanation text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'final', 'reviewed')),
  entered_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT daily_balance_entries_location_date_unique UNIQUE (location, entry_date)
);

CREATE TABLE IF NOT EXISTS public.daily_balance_expenses (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  daily_balance_entry_id uuid NOT NULL REFERENCES public.daily_balance_entries(id) ON DELETE CASCADE,
  expense_status text NOT NULL DEFAULT 'approved' CHECK (expense_status IN ('approved', 'unapproved')),
  item text NOT NULL,
  amount numeric(15, 2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_auth_id ON public.staff(auth_id);
CREATE INDEX IF NOT EXISTS idx_staff_role ON public.staff(role);
CREATE INDEX IF NOT EXISTS idx_daily_balance_entries_date ON public.daily_balance_entries(entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_balance_entries_entered_by ON public.daily_balance_entries(entered_by);
CREATE INDEX IF NOT EXISTS idx_daily_balance_entries_location_date ON public.daily_balance_entries(location, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_balance_expenses_entry ON public.daily_balance_expenses(daily_balance_entry_id);
CREATE INDEX IF NOT EXISTS idx_daily_balance_expenses_status ON public.daily_balance_expenses(expense_status);

ALTER TABLE public.daily_balance_entries
  ALTER COLUMN entered_by DROP NOT NULL;

ALTER TABLE public.daily_balance_entries
  DROP CONSTRAINT IF EXISTS daily_balance_entries_entered_by_fkey;

ALTER TABLE public.daily_balance_entries
  ADD CONSTRAINT daily_balance_entries_entered_by_fkey
  FOREIGN KEY (entered_by) REFERENCES auth.users(id) ON DELETE SET NULL;

DROP TRIGGER IF EXISTS set_staff_updated_at ON public.staff;
CREATE TRIGGER set_staff_updated_at
  BEFORE UPDATE ON public.staff
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_daily_balance_entries_updated_at ON public.daily_balance_entries;
CREATE TRIGGER set_daily_balance_entries_updated_at
  BEFORE UPDATE ON public.daily_balance_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
  IF to_regclass('public.monthly_balance_summary') IS NOT NULL THEN
    IF (
      SELECT c.relkind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'monthly_balance_summary'
    ) = 'v' THEN
      EXECUTE 'DROP VIEW public.monthly_balance_summary CASCADE';
    ELSIF (
      SELECT c.relkind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'monthly_balance_summary'
    ) = 'm' THEN
      EXECUTE 'DROP MATERIALIZED VIEW public.monthly_balance_summary CASCADE';
    ELSE
      EXECUTE 'DROP TABLE public.monthly_balance_summary CASCADE';
    END IF;
  END IF;

  IF to_regclass('public.daily_balance_summary') IS NOT NULL THEN
    IF (
      SELECT c.relkind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'daily_balance_summary'
    ) = 'v' THEN
      EXECUTE 'DROP VIEW public.daily_balance_summary CASCADE';
    ELSIF (
      SELECT c.relkind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'daily_balance_summary'
    ) = 'm' THEN
      EXECUTE 'DROP MATERIALIZED VIEW public.daily_balance_summary CASCADE';
    ELSE
      EXECUTE 'DROP TABLE public.daily_balance_summary CASCADE';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE VIEW public.daily_balance_summary AS
SELECT
  e.id AS daily_entry_id,
  e.location,
  e.entry_date,
  e.entered_by,
  e.status,
  e.opening_balance,
  e.normal_sales + e.virtual_sales AS total_sales,
  e.normal_payout + e.virtual_payout AS total_payout,
  COALESCE(SUM(x.amount) FILTER (WHERE x.expense_status = 'approved'), 0) AS total_approved_expenses,
  COALESCE(SUM(x.amount) FILTER (WHERE x.expense_status = 'unapproved'), 0) AS total_unapproved_expenses,
  e.cash_in,
  e.cash_out,
  e.opening_balance
    + e.normal_sales + e.virtual_sales
    + e.cash_in
    - e.normal_payout - e.virtual_payout
    - e.cash_out
    - COALESCE(SUM(x.amount) FILTER (WHERE x.expense_status = 'approved'), 0) AS expected_closing,
  e.cash_at_hand AS actual_closing,
  e.opening_balance
    + e.normal_sales + e.virtual_sales
    + e.cash_in
    - e.normal_payout - e.virtual_payout
    - e.cash_out
    - COALESCE(SUM(x.amount) FILTER (WHERE x.expense_status = 'approved'), 0)
    - e.cash_at_hand AS variance,
  e.created_at,
  e.updated_at
FROM public.daily_balance_entries e
LEFT JOIN public.daily_balance_expenses x
  ON x.daily_balance_entry_id = e.id
GROUP BY e.id;

ALTER VIEW public.daily_balance_summary SET (security_invoker = true);

CREATE OR REPLACE VIEW public.monthly_balance_summary AS
SELECT
  location,
  date_trunc('month', entry_date)::date AS month_start,
  (date_trunc('month', entry_date) + interval '1 month - 1 day')::date AS month_end,
  COUNT(*)::int AS days_entered,
  SUM(total_sales) AS total_sales,
  SUM(total_payout) AS total_payout,
  SUM(total_approved_expenses) AS total_approved_expenses,
  SUM(total_unapproved_expenses) AS total_unapproved_expenses,
  SUM(cash_in) AS total_cash_in,
  SUM(cash_out) AS total_cash_out,
  SUM(variance) AS total_variance
FROM public.daily_balance_summary
GROUP BY location, date_trunc('month', entry_date);

ALTER VIEW public.monthly_balance_summary SET (security_invoker = true);

ALTER TABLE public.staff DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_balance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_balance_expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff_select_authenticated" ON public.staff;
DROP POLICY IF EXISTS "staff_insert_own_profile" ON public.staff;
DROP POLICY IF EXISTS "staff_update_own_profile" ON public.staff;
DROP POLICY IF EXISTS "staff_admin_manage" ON public.staff;

DROP POLICY IF EXISTS "Users can view all staff" ON public.staff;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.staff;
DROP POLICY IF EXISTS "Admins can manage all staff" ON public.staff;

DROP POLICY IF EXISTS "entries_select_own_or_admin" ON public.daily_balance_entries;
DROP POLICY IF EXISTS "entries_insert_own" ON public.daily_balance_entries;
DROP POLICY IF EXISTS "entries_update_own_or_admin" ON public.daily_balance_entries;
DROP POLICY IF EXISTS "entries_delete_own_or_admin" ON public.daily_balance_entries;

DROP POLICY IF EXISTS "Users can view entries for their location" ON public.daily_balance_entries;
DROP POLICY IF EXISTS "Authenticated users can create entries" ON public.daily_balance_entries;
DROP POLICY IF EXISTS "Users can update their own entries" ON public.daily_balance_entries;
DROP POLICY IF EXISTS "Admins can delete entries" ON public.daily_balance_entries;

DROP POLICY IF EXISTS "entries_public_select_no_login" ON public.daily_balance_entries;
CREATE POLICY "entries_public_select_no_login"
  ON public.daily_balance_entries FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "entries_public_insert_no_login" ON public.daily_balance_entries;
CREATE POLICY "entries_public_insert_no_login"
  ON public.daily_balance_entries FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "entries_public_update_no_login" ON public.daily_balance_entries;
CREATE POLICY "entries_public_update_no_login"
  ON public.daily_balance_entries FOR UPDATE
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "entries_public_delete_no_login" ON public.daily_balance_entries;
CREATE POLICY "entries_public_delete_no_login"
  ON public.daily_balance_entries FOR DELETE
  USING (true);

DROP POLICY IF EXISTS "expenses_select_own_or_admin" ON public.daily_balance_expenses;
DROP POLICY IF EXISTS "expenses_insert_own_or_admin" ON public.daily_balance_expenses;
DROP POLICY IF EXISTS "expenses_update_own_or_admin" ON public.daily_balance_expenses;
DROP POLICY IF EXISTS "expenses_delete_own_or_admin" ON public.daily_balance_expenses;

DROP POLICY IF EXISTS "Users can view expenses for their entries" ON public.daily_balance_expenses;
DROP POLICY IF EXISTS "Users can manage expenses in draft entries" ON public.daily_balance_expenses;

DROP POLICY IF EXISTS "expenses_public_select_no_login" ON public.daily_balance_expenses;
CREATE POLICY "expenses_public_select_no_login"
  ON public.daily_balance_expenses FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "expenses_public_insert_no_login" ON public.daily_balance_expenses;
CREATE POLICY "expenses_public_insert_no_login"
  ON public.daily_balance_expenses FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "expenses_public_update_no_login" ON public.daily_balance_expenses;
CREATE POLICY "expenses_public_update_no_login"
  ON public.daily_balance_expenses FOR UPDATE
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "expenses_public_delete_no_login" ON public.daily_balance_expenses;
CREATE POLICY "expenses_public_delete_no_login"
  ON public.daily_balance_expenses FOR DELETE
  USING (true);

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_balance_entries TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_balance_expenses TO anon;
GRANT SELECT ON public.daily_balance_summary TO anon;
GRANT SELECT ON public.monthly_balance_summary TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_balance_entries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_balance_expenses TO authenticated;
GRANT SELECT ON public.daily_balance_summary TO authenticated;
GRANT SELECT ON public.monthly_balance_summary TO authenticated;
