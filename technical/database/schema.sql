-- ============================================
-- CONVOAK DATABASE SCHEMA
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- 1. TABLES
-- ============================================

-- Users table (extends Supabase auth.users)
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE CHECK (
        username ~ '^[a-z0-9_.]{2,32}$' AND 
        username !~ '\\.\\.'
    ),
    display_name TEXT,
    date_of_birth DATE,
    avatar_gradient_start TEXT,
    avatar_gradient_end TEXT,
    onboarding_completed BOOLEAN DEFAULT FALSE,
    name TEXT,
    avatar_url TEXT,
    auth_provider TEXT CHECK (auth_provider IN ('email', 'google', 'microsoft')),
    is_online BOOLEAN DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Convos table
CREATE TABLE public.convos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    last_activity_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Messages table
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    convo_id UUID NOT NULL REFERENCES public.convos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User convo visits table (for "My Convos")
CREATE TABLE public.user_convo_visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    convo_id UUID NOT NULL REFERENCES public.convos(id) ON DELETE CASCADE,
    last_visited TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, convo_id)
);

-- ============================================
-- 2. INDEXES
-- ============================================

-- For fetching active convos (sorted by recent activity)
CREATE INDEX idx_convos_last_activity ON public.convos(last_activity_at DESC NULLS LAST);

-- For searching convos by slug
CREATE INDEX idx_convos_slug ON public.convos(slug);

-- For fetching messages in a convo
CREATE INDEX idx_messages_convo_id ON public.messages(convo_id, created_at);

-- For fetching user's visited convos
CREATE INDEX idx_user_convo_visits_user ON public.user_convo_visits(user_id, last_visited DESC);

-- For online status queries
CREATE INDEX idx_users_online ON public.users(is_online) WHERE is_online = TRUE;

-- ============================================
-- 3. ROW LEVEL SECURITY
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.convos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_convo_visits ENABLE ROW LEVEL SECURITY;

-- USERS policies
CREATE POLICY "Anyone can view user profiles"
ON public.users FOR SELECT
USING (true);

CREATE POLICY "Users can insert their own profile"
ON public.users FOR INSERT
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
ON public.users FOR UPDATE
USING (auth.uid() = id);

-- CONVOS policies
CREATE POLICY "Anyone can view convos"
ON public.convos FOR SELECT
USING (true);

CREATE POLICY "Authenticated users can create convos"
ON public.convos FOR INSERT
WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Creators can update their convos"
ON public.convos FOR UPDATE
USING (auth.uid() = created_by);

-- MESSAGES policies
CREATE POLICY "Anyone can view messages"
ON public.messages FOR SELECT
USING (true);

CREATE POLICY "Authenticated users can send messages"
ON public.messages FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- USER_CONVO_VISITS policies
CREATE POLICY "Users can view their own visits"
ON public.user_convo_visits FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own visits"
ON public.user_convo_visits FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own visits"
ON public.user_convo_visits FOR UPDATE
USING (auth.uid() = user_id);

-- ============================================
-- 4. FUNCTIONS
-- ============================================

-- Function to update last_activity_at when a message is sent
CREATE OR REPLACE FUNCTION update_convo_activity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.convos
    SET last_activity_at = NOW()
    WHERE id = NEW.convo_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function after message insert
CREATE TRIGGER on_message_insert
AFTER INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION update_convo_activity();

-- Function to upsert user convo visit
CREATE OR REPLACE FUNCTION track_convo_visit(p_user_id UUID, p_convo_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.user_convo_visits (user_id, convo_id, last_visited)
    VALUES (p_user_id, p_convo_id, NOW())
    ON CONFLICT (user_id, convo_id)
    DO UPDATE SET last_visited = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. REALTIME
-- ============================================

-- Enable realtime for messages (for live chat)
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

-- Enable realtime for user online status (optional)
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;

-- ============================================
-- 6. HELPER VIEWS (OPTIONAL)
-- ============================================

-- View for active convos (convos with messages)
CREATE VIEW public.active_convos AS
SELECT 
    c.*,
    COUNT(m.id) as message_count
FROM public.convos c
LEFT JOIN public.messages m ON m.convo_id = c.id
WHERE c.last_activity_at IS NOT NULL
GROUP BY c.id
ORDER BY c.last_activity_at DESC;
