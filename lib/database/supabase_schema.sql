-- =============================================================================
-- P.O.I.S.E. Cloud Database Schema (Supabase / PostgreSQL)
-- Implements the P.O.I.S.E. ERD and Architecture Specification
-- =============================================================================

-- Enable pgcrypto for UUID generation if not already enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------------------------
-- 1. PROFILES TABLE
-- Maps 1:1 to auth.users.id
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profiles IS 'User profile information matching auth.users';

-- -----------------------------------------------------------------------------
-- 2. DEVICES TABLE
-- Registered and paired ESP32 wearable devices
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_name TEXT NOT NULL,
    paired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_devices_user_id ON public.devices(user_id);
COMMENT ON TABLE public.devices IS 'POISE hardware wearable devices paired with a user profile';

-- -----------------------------------------------------------------------------
-- 3. MODES TABLE
-- Posture detection sensitivity presets (Normal, Focus, Leisure, Commuting)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.modes (
    id INT PRIMARY KEY,
    mode_name TEXT NOT NULL,
    angle_threshold_deg NUMERIC NOT NULL,
    forgiveness_time_sec NUMERIC NOT NULL
);

COMMENT ON TABLE public.modes IS 'Activity posture preset configurations';

-- Seed default posture modes
INSERT INTO public.modes (id, mode_name, angle_threshold_deg, forgiveness_time_sec)
VALUES
    (1, 'Normal', 15, 2),
    (2, 'Focus', 10, 1),
    (3, 'Leisure', 20, 3),
    (4, 'Commuting', 25, 5)
ON CONFLICT (id) DO UPDATE
SET mode_name = EXCLUDED.mode_name,
    angle_threshold_deg = EXCLUDED.angle_threshold_deg,
    forgiveness_time_sec = EXCLUDED.forgiveness_time_sec;

-- -----------------------------------------------------------------------------
-- 4. SESSIONS TABLE
-- Posture tracking monitoring sessions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES public.devices(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    mode_id INT NOT NULL REFERENCES public.modes(id) ON DELETE RESTRICT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    baseline_angle NUMERIC NOT NULL DEFAULT 0.0
);

-- Ensure device_id is nullable if existing table had a NOT NULL constraint
ALTER TABLE IF EXISTS public.sessions ALTER COLUMN device_id DROP NOT NULL;
ALTER TABLE IF EXISTS public.sessions ADD COLUMN IF NOT EXISTS baseline_angle NUMERIC NOT NULL DEFAULT 0.0;

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON public.sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON public.sessions(started_at);
COMMENT ON TABLE public.sessions IS 'Active or completed posture monitoring sessions';

-- -----------------------------------------------------------------------------
-- 5. POSTURE_EVENTS TABLE
-- Confirmed slouch/deviation events detected by the ESP32 edge node
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posture_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    corrected_at TIMESTAMPTZ,
    correction_time_sec NUMERIC,
    tilt_angle NUMERIC NOT NULL,
    duration_sec NUMERIC NOT NULL,
    feedback_triggered BOOLEAN NOT NULL DEFAULT true,
    synced BOOLEAN NOT NULL DEFAULT true
);

-- Migrations for existing posture_events tables
ALTER TABLE IF EXISTS public.posture_events ADD COLUMN IF NOT EXISTS corrected_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.posture_events ADD COLUMN IF NOT EXISTS correction_time_sec NUMERIC;

CREATE INDEX IF NOT EXISTS idx_posture_events_session_id ON public.posture_events(session_id);
CREATE INDEX IF NOT EXISTS idx_posture_events_occurred_at ON public.posture_events(occurred_at);
COMMENT ON TABLE public.posture_events IS 'Confirmed slouch posture events synced from mobile buffer';

-- -----------------------------------------------------------------------------
-- 6. AUTOMATED TIMESTAMP TRIGGERS
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
DROP TRIGGER IF EXISTS trg_devices_updated_at ON public.devices;
DROP TRIGGER IF EXISTS trg_sessions_updated_at ON public.sessions;
DROP FUNCTION IF EXISTS public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_devices_updated_at
    BEFORE UPDATE ON public.devices
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_sessions_updated_at
    BEFORE UPDATE ON public.sessions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- -----------------------------------------------------------------------------
-- 7. AUTOMATIC USER PROFILE CREATION TRIGGER
-- Triggers on new user sign-up in Supabase Auth (Email or OAuth)
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, created_at, updated_at)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data->>'full_name',
            NEW.raw_user_meta_data->>'name',
            split_part(NEW.email, '@', 1)
        ),
        now(),
        now()
    )
    ON CONFLICT (id) DO UPDATE
    SET full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- -----------------------------------------------------------------------------
-- 8. ROW LEVEL SECURITY (RLS) POLICIES
-- Scoped to auth.uid()
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posture_events ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can delete their own profile" ON public.profiles;
CREATE POLICY "Users can delete their own profile"
    ON public.profiles FOR DELETE
    USING (auth.uid() = id);

-- Devices Policies
DROP POLICY IF EXISTS "Users can view their own devices" ON public.devices;
CREATE POLICY "Users can view their own devices"
    ON public.devices FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own devices" ON public.devices;
CREATE POLICY "Users can insert their own devices"
    ON public.devices FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own devices" ON public.devices;
CREATE POLICY "Users can update their own devices"
    ON public.devices FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own devices" ON public.devices;
CREATE POLICY "Users can delete their own devices"
    ON public.devices FOR DELETE
    USING (auth.uid() = user_id);

-- Modes Policies (Public/Authenticated Read Only, Authenticated can seed)
DROP POLICY IF EXISTS "Anyone can view modes" ON public.modes;
CREATE POLICY "Anyone can view modes"
    ON public.modes FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert modes" ON public.modes;
CREATE POLICY "Authenticated users can insert modes"
    ON public.modes FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Sessions Policies
DROP POLICY IF EXISTS "Users can view their own sessions" ON public.sessions;
CREATE POLICY "Users can view their own sessions"
    ON public.sessions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own sessions" ON public.sessions;
CREATE POLICY "Users can insert their own sessions"
    ON public.sessions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own sessions" ON public.sessions;
CREATE POLICY "Users can update their own sessions"
    ON public.sessions FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own sessions" ON public.sessions;
CREATE POLICY "Users can delete their own sessions"
    ON public.sessions FOR DELETE
    USING (auth.uid() = user_id);

-- Posture Events Policies (scoped via session ownership)
DROP POLICY IF EXISTS "Users can view posture events of their sessions" ON public.posture_events;
CREATE POLICY "Users can view posture events of their sessions"
    ON public.posture_events FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE public.sessions.id = posture_events.session_id
              AND public.sessions.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can insert posture events to their sessions" ON public.posture_events;
CREATE POLICY "Users can insert posture events to their sessions"
    ON public.posture_events FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE public.sessions.id = posture_events.session_id
              AND public.sessions.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can update posture events of their sessions" ON public.posture_events;
CREATE POLICY "Users can update posture events of their sessions"
    ON public.posture_events FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE public.sessions.id = posture_events.session_id
              AND public.sessions.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can delete posture events of their sessions" ON public.posture_events;
CREATE POLICY "Users can delete posture events of their sessions"
    ON public.posture_events FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE public.sessions.id = posture_events.session_id
              AND public.sessions.user_id = auth.uid()
        )
    );

-- -----------------------------------------------------------------------------
-- 9. USER ACCOUNT & DATA MANAGEMENT RPC FUNCTIONS
-- -----------------------------------------------------------------------------

-- 1. Delete user account and cascade delete all associated profiles and telemetry
DROP FUNCTION IF EXISTS public.delete_user_account();
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

-- 2. Delete all posture telemetry, sessions, and devices for the authenticated user
DROP FUNCTION IF EXISTS public.delete_user_posture_data();
CREATE OR REPLACE FUNCTION public.delete_user_posture_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.posture_events
    WHERE session_id IN (
        SELECT id FROM public.sessions WHERE user_id = auth.uid()
    );

    DELETE FROM public.sessions
    WHERE user_id = auth.uid();

    DELETE FROM public.devices
    WHERE user_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_posture_data() TO authenticated;

-- 3. Set or update a user's password (supports linking password to OAuth accounts)
DROP FUNCTION IF EXISTS public.set_user_password(text, text);
CREATE OR REPLACE FUNCTION public.set_user_password(user_email text, new_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
BEGIN
    UPDATE auth.users
    SET encrypted_password = crypt(new_password, gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        updated_at = now()
    WHERE lower(email) = lower(trim(user_email));
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_password(text, text) TO anon, authenticated;

-- 4. Auto-confirm user email upon registration (bypasses manual email link clicking)
DROP TRIGGER IF EXISTS trg_auto_confirm_user_email ON auth.users;
DROP FUNCTION IF EXISTS public.auto_confirm_user_email();
CREATE OR REPLACE FUNCTION public.auto_confirm_user_email()
RETURNS trigger AS $$
BEGIN
    NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, now());
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_auto_confirm_user_email
    BEFORE INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.auto_confirm_user_email();

-- 5. RPC function to explicitly confirm a user's email if already created
DROP FUNCTION IF EXISTS public.confirm_user_email(text);
CREATE OR REPLACE FUNCTION public.confirm_user_email(user_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    UPDATE auth.users
    SET 
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        confirmed_at = COALESCE(confirmed_at, now()),
        updated_at = now()
    WHERE lower(email) = lower(trim(user_email));

    RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_user_email(text) TO anon, authenticated;

