-- Full application schema reconstructed from backend/src usage.
-- Source analyzed:
-- - auth
-- - admin
-- - subscriptions
-- - payments
-- - campaigns
-- - queue worker
-- - templates
-- - telegram
-- - whatsapp
-- - leads
-- - sheets
--
-- Notes:
-- 1. This is an inferred plain PostgreSQL schema for the application tables.
-- 2. Supabase internal schemas (auth/realtime/storage/vault) are intentionally excluded.
-- 3. Supabase Storage bucket "template-media" is not covered by SQL alone.

BEGIN;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'subscription_status') THEN
        CREATE TYPE subscription_status AS ENUM ('none', 'trial', 'active', 'canceled', 'expired', 'blocked');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'campaign_status') THEN
        CREATE TYPE campaign_status AS ENUM ('running', 'stopped');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'campaign_mode') THEN
        CREATE TYPE campaign_mode AS ENUM ('multi');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'campaign_channel') THEN
        CREATE TYPE campaign_channel AS ENUM ('wa', 'tg');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'campaign_job_status') THEN
        CREATE TYPE campaign_job_status AS ENUM ('pending', 'processing', 'sent', 'failed', 'skipped');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'referral_status') THEN
        CREATE TYPE referral_status AS ENUM ('registered', 'rewarded');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    last_login timestamptz,
    is_verified boolean NOT NULL DEFAULT false,
    full_name text,
    gender text,
    telegram text,
    birthday date,
    city text,
    email text,
    email_verified boolean NOT NULL DEFAULT false,
    is_blocked boolean NOT NULL DEFAULT false,
    is_admin boolean NOT NULL DEFAULT false,
    referral_code text UNIQUE,
    referred_by_user_id uuid,
    timezone text DEFAULT 'Europe/Moscow',
    gsheet_url text,
    tg_session text,
    CONSTRAINT users_referred_by_fkey
        FOREIGN KEY (referred_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL
);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_blocked boolean NOT NULL DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS referral_code text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS referred_by_user_id uuid;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'Europe/Moscow';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gsheet_url text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS tg_session text;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_referred_by_fkey'
          AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_referred_by_fkey
            FOREIGN KEY (referred_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_users_created_at ON public.users(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON public.users(referral_code);
CREATE INDEX IF NOT EXISTS idx_users_is_admin ON public.users(is_admin);
CREATE INDEX IF NOT EXISTS idx_users_is_blocked ON public.users(is_blocked);

CREATE TABLE IF NOT EXISTS public.otp_codes (
    phone text PRIMARY KEY,
    code text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    last_sent_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.otp_codes ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE public.otp_codes ADD COLUMN IF NOT EXISTS attempts integer NOT NULL DEFAULT 0;
ALTER TABLE public.otp_codes ADD COLUMN IF NOT EXISTS last_sent_at timestamptz;
ALTER TABLE public.otp_codes ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_otp_codes_expires_at ON public.otp_codes(expires_at);

CREATE TABLE IF NOT EXISTS public.subscriptions (
    user_id uuid PRIMARY KEY,
    status subscription_status NOT NULL DEFAULT 'none',
    plan_code text NOT NULL DEFAULT 'base',
    provider text,
    trial_started_at timestamptz,
    trial_ends_at timestamptz,
    current_period_start timestamptz,
    current_period_end timestamptz,
    cancel_at_period_end boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT subscriptions_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_trial_ends_at ON public.subscriptions(trial_ends_at);
CREATE INDEX IF NOT EXISTS idx_subscriptions_current_period_end ON public.subscriptions(current_period_end);

CREATE TABLE IF NOT EXISTS public.referrals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_user_id uuid NOT NULL,
    referred_user_id uuid NOT NULL UNIQUE,
    status referral_status NOT NULL DEFAULT 'registered',
    reward_type text NOT NULL DEFAULT 'days',
    reward_value integer NOT NULL DEFAULT 7,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT referrals_referrer_fkey
        FOREIGN KEY (referrer_user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    CONSTRAINT referrals_referred_fkey
        FOREIGN KEY (referred_user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals(referrer_user_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals(status);

CREATE TABLE IF NOT EXISTS public.payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    provider text NOT NULL,
    amount_rub numeric(12,2) NOT NULL,
    status text NOT NULL DEFAULT 'created',
    order_id text,
    provider_payment_id text,
    paid_at timestamptz,
    current_period_end timestamptz,
    raw jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payments_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_order_id
    ON public.payments(order_id)
    WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_user_id ON public.payments(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_provider_payment_id ON public.payments(provider_payment_id);

CREATE TABLE IF NOT EXISTS public.lead_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name text NOT NULL,
    phone text NOT NULL,
    birth_date date,
    city text NOT NULL,
    telegram text,
    consent_personal boolean NOT NULL,
    consent_marketing boolean NOT NULL DEFAULT false,
    user_agent text,
    ip text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lead_requests_created_at ON public.lead_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lead_requests_phone ON public.lead_requests(phone);

CREATE TABLE IF NOT EXISTS public.message_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    sheet_row integer NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    "order" integer NOT NULL DEFAULT 1,
    title text,
    text text,
    media_url text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT message_templates_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    CONSTRAINT uq_message_templates_user_sheet_row UNIQUE (user_id, sheet_row)
);

CREATE INDEX IF NOT EXISTS idx_message_templates_user_order
    ON public.message_templates(user_id, "order", updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_templates_enabled
    ON public.message_templates(user_id, enabled);

CREATE TABLE IF NOT EXISTS public.whatsapp_groups (
    user_id uuid NOT NULL,
    wa_group_id text NOT NULL,
    subject text,
    participants_count integer,
    is_announcement boolean NOT NULL DEFAULT false,
    is_restricted boolean NOT NULL DEFAULT false,
    is_selected boolean NOT NULL DEFAULT true,
    send_time text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, wa_group_id),
    CONSTRAINT whatsapp_groups_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_groups_user_selected
    ON public.whatsapp_groups(user_id, is_selected);

CREATE TABLE IF NOT EXISTS public.telegram_groups (
    user_id uuid NOT NULL,
    tg_chat_id text NOT NULL,
    tg_type text,
    tg_access_hash text,
    title text,
    participants_count integer,
    is_selected boolean NOT NULL DEFAULT true,
    send_time text,
    avatar_url text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, tg_chat_id),
    CONSTRAINT telegram_groups_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_telegram_groups_user_selected
    ON public.telegram_groups(user_id, is_selected);

CREATE TABLE IF NOT EXISTS public.template_group_targets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    template_id uuid NOT NULL,
    group_jid text NOT NULL,
    channel campaign_channel NOT NULL DEFAULT 'wa',
    enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT template_group_targets_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    CONSTRAINT template_group_targets_template_fkey
        FOREIGN KEY (template_id) REFERENCES public.message_templates(id) ON DELETE CASCADE,
    CONSTRAINT uq_template_group_targets UNIQUE (user_id, template_id, group_jid, channel)
);

CREATE INDEX IF NOT EXISTS idx_template_targets_template
    ON public.template_group_targets(template_id, channel, enabled);
CREATE INDEX IF NOT EXISTS idx_template_targets_user
    ON public.template_group_targets(user_id, channel);

CREATE TABLE IF NOT EXISTS public.campaigns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    status campaign_status NOT NULL DEFAULT 'running',
    mode campaign_mode NOT NULL DEFAULT 'multi',
    channel campaign_channel NOT NULL DEFAULT 'wa',
    time_from text NOT NULL DEFAULT '08:00',
    time_to text NOT NULL DEFAULT '17:00',
    timezone text NOT NULL DEFAULT 'Europe/Moscow',
    between_groups_sec_min integer NOT NULL DEFAULT 2,
    between_groups_sec_max integer NOT NULL DEFAULT 3,
    between_templates_min_min integer NOT NULL DEFAULT 2,
    between_templates_min_max integer NOT NULL DEFAULT 3,
    repeat_enabled boolean NOT NULL DEFAULT false,
    repeat_min_min integer,
    repeat_min_max integer,
    next_repeat_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT campaigns_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_campaigns_user_status_channel
    ON public.campaigns(user_id, status, channel, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_campaigns_running_per_channel
    ON public.campaigns(user_id, channel)
    WHERE status = 'running';

CREATE TABLE IF NOT EXISTS public.campaign_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id uuid NOT NULL,
    user_id uuid NOT NULL,
    group_jid text NOT NULL,
    channel campaign_channel NOT NULL DEFAULT 'wa',
    template_id uuid NOT NULL,
    status campaign_job_status NOT NULL DEFAULT 'pending',
    scheduled_at timestamptz NOT NULL,
    sent_at timestamptz,
    error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT campaign_jobs_campaign_fkey
        FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE,
    CONSTRAINT campaign_jobs_user_fkey
        FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    CONSTRAINT campaign_jobs_template_fkey
        FOREIGN KEY (template_id) REFERENCES public.message_templates(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_campaign_jobs_campaign
    ON public.campaign_jobs(campaign_id, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_campaign_jobs_campaign_status
    ON public.campaign_jobs(campaign_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_campaign_jobs_user_status
    ON public.campaign_jobs(user_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_campaign_jobs_pending
    ON public.campaign_jobs(status, scheduled_at);

COMMIT;
