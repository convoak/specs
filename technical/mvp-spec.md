# Convoak MVP - Technical Specification

## Project Overview

Convoak is a real-time chat platform where users create or join conversations ("convos") by typing topics into a search bar. The core loop: type a topic → land in a convo → read/send messages → discover other convos via sidebar.

**Key Principles:**
- Anonymous users can browse everything; auth only required to send messages
- Minimal landing page (Google-style: logo + search bar)
- Convos are fragmented by exact topic match (natural deduplication via slug)
- Real-time messaging via WebSocket subscriptions

---

## Tech Stack

- **Frontend:** React 18+ with Vite
- **Styling:** Tailwind CSS
- **Backend/Database:** Supabase (PostgreSQL + Auth + Realtime)
- **Email Provider:** Resend (for OTP delivery)
- **Routing:** React Router v6
- **State Management:** React hooks (no Redux needed for MVP)

---

## URL Structure

```
/                     → Landing page
/c/:slug              → Convo view
/auth/callback        → OAuth redirect handler
```

**Slug Rules:**
- Lowercase
- Spaces → `%2B` (URL-encoded `+`)
- Special characters stripped (except alphanumeric)
- Multiple `%2B` collapsed
- Max length: 100 characters
- UI displays decoded version (e.g., `javascript+help`)

**Examples:**
| User Input | URL Slug | Display |
|------------|----------|--------|
| Hello World | hello%2Bworld | hello+world |
| JavaScript Help! | javascript%2Bhelp | javascript+help |
| What's up | whats%2Bup | whats+up |

---

## Database Schema

### Tables

**users**
```sql
id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE
email           TEXT UNIQUE NOT NULL
name            TEXT
avatar_url      TEXT
auth_provider   TEXT CHECK (auth_provider IN ('email', 'google', 'microsoft'))
is_online       BOOLEAN DEFAULT FALSE
last_seen_at    TIMESTAMPTZ
created_at      TIMESTAMPTZ DEFAULT NOW()
```

**convos**
```sql
id                UUID PRIMARY KEY DEFAULT gen_random_uuid()
topic             TEXT NOT NULL              -- Display name: "JavaScript Help"
slug              TEXT UNIQUE NOT NULL       -- URL-safe: "javascript-help"
created_by        UUID REFERENCES users(id) ON DELETE SET NULL
last_activity_at  TIMESTAMPTZ               -- Updated on each message
created_at        TIMESTAMPTZ DEFAULT NOW()
```

**messages**
```sql
id          UUID PRIMARY KEY DEFAULT gen_random_uuid()
convo_id    UUID NOT NULL REFERENCES convos(id) ON DELETE CASCADE
user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
content     TEXT NOT NULL
created_at  TIMESTAMPTZ DEFAULT NOW()
```

**user_convo_visits**
```sql
id            UUID PRIMARY KEY DEFAULT gen_random_uuid()
user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
convo_id      UUID NOT NULL REFERENCES convos(id) ON DELETE CASCADE
last_visited  TIMESTAMPTZ DEFAULT NOW()
UNIQUE(user_id, convo_id)
```

### Indexes

```sql
CREATE INDEX idx_convos_last_activity ON convos(last_activity_at DESC NULLS LAST);
CREATE INDEX idx_convos_slug ON convos(slug);
CREATE INDEX idx_messages_convo_id ON messages(convo_id, created_at);
CREATE INDEX idx_user_convo_visits_user ON user_convo_visits(user_id, last_visited DESC);
CREATE INDEX idx_users_online ON users(is_online) WHERE is_online = TRUE;
```

### Row Level Security (RLS)

```sql
-- Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE convos ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_convo_visits ENABLE ROW LEVEL SECURITY;

-- Users: public read, self write
CREATE POLICY "Anyone can view users" ON users FOR SELECT USING (true);
CREATE POLICY "Users can insert own profile" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON users FOR UPDATE USING (auth.uid() = id);

-- Convos: public read, authenticated create
CREATE POLICY "Anyone can view convos" ON convos FOR SELECT USING (true);
CREATE POLICY "Authenticated can create convos" ON convos FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Messages: public read, authenticated create
CREATE POLICY "Anyone can view messages" ON messages FOR SELECT USING (true);
CREATE POLICY "Authenticated can send messages" ON messages FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Visits: private to user
CREATE POLICY "Users view own visits" ON user_convo_visits FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own visits" ON user_convo_visits FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own visits" ON user_convo_visits FOR UPDATE USING (auth.uid() = user_id);
```

### Database Functions

```sql
-- Auto-update last_activity_at on new message
CREATE OR REPLACE FUNCTION update_convo_activity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE convos SET last_activity_at = NOW() WHERE id = NEW.convo_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_message_insert
AFTER INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION update_convo_activity();

-- Upsert convo visit
CREATE OR REPLACE FUNCTION track_convo_visit(p_user_id UUID, p_convo_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO user_convo_visits (user_id, convo_id, last_visited)
    VALUES (p_user_id, p_convo_id, NOW())
    ON CONFLICT (user_id, convo_id) DO UPDATE SET last_visited = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Realtime

```sql
-- Messages for live chat updates
ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- Users for online status updates
ALTER PUBLICATION supabase_realtime ADD TABLE users;
```

---

## Authentication

### Methods
1. **Email OTP** - Primary method
2. **Google OAuth** - Social login
3. **Microsoft OAuth** - Social login

### Auth Flow

**Email OTP:**
1. User enters email
2. Call `supabase.auth.signInWithOtp({ email })`
3. User receives 6-digit code (valid 10 minutes)
4. User enters code
5. Call `supabase.auth.verifyOtp({ email, token, type: 'email' })`
6. On success: session created, redirect to original convo

**OAuth:**
1. User clicks Google/Microsoft button
2. Call `supabase.auth.signInWithOAuth({ provider, options: { redirectTo } })`
3. User completes OAuth flow
4. Redirect to `/auth/callback`
5. Exchange code for session
6. Redirect to original convo

### Auth Trigger Point
- Auth modal appears ONLY when anonymous user tries to send a message
- Store intended message in state, send after auth completes
- Store current convo slug to redirect back after auth

### User Profile Creation
On first auth, create user profile in `users` table:
```javascript
// In auth callback or onAuthStateChange
const { data: { user } } = await supabase.auth.getUser()
if (user) {
  await supabase.from('users').upsert({
    id: user.id,
    email: user.email,
    name: user.user_metadata.full_name || user.email.split('@')[0],
    avatar_url: user.user_metadata.avatar_url || null,
    auth_provider: user.app_metadata.provider || 'email',
  })
}
```

---

## Security Implementation

### Input Validation

**Message Content:**
```javascript
const MAX_MESSAGE_LENGTH = 5000
const MIN_MESSAGE_LENGTH = 1

function validateMessage(content) {
  const trimmed = content.trim()
  if (trimmed.length < MIN_MESSAGE_LENGTH) {
    return { valid: false, error: 'Message cannot be empty' }
  }
  if (trimmed.length > MAX_MESSAGE_LENGTH) {
    return { valid: false, error: `Message cannot exceed ${MAX_MESSAGE_LENGTH} characters` }
  }
  return { valid: true, content: trimmed }
}
```

**Topic/Slug:**
```javascript
const MAX_TOPIC_LENGTH = 100
const MIN_TOPIC_LENGTH = 1

function validateTopic(topic) {
  const trimmed = topic.trim()
  if (trimmed.length < MIN_TOPIC_LENGTH) {
    return { valid: false, error: 'Topic cannot be empty' }
  }
  if (trimmed.length > MAX_TOPIC_LENGTH) {
    return { valid: false, error: `Topic cannot exceed ${MAX_TOPIC_LENGTH} characters` }
  }
  return { valid: true, topic: trimmed }
}
```

### XSS Prevention

**Never use `dangerouslySetInnerHTML` with user content.**

Messages are rendered as plain text:
```jsx
// CORRECT
<p>{message.content}</p>

// NEVER DO THIS
<p dangerouslySetInnerHTML={{ __html: message.content }} />
```

If you need to render links in messages later, use a sanitization library like DOMPurify.

### Rate Limiting

Implement client-side rate limiting to prevent spam:
```javascript
const RATE_LIMIT_MESSAGES = 10      // max messages
const RATE_LIMIT_WINDOW = 60000     // per 60 seconds

class RateLimiter {
  constructor(limit, window) {
    this.limit = limit
    this.window = window
    this.timestamps = []
  }

  canProceed() {
    const now = Date.now()
    this.timestamps = this.timestamps.filter(t => now - t < this.window)
    
    if (this.timestamps.length >= this.limit) {
      return false
    }
    
    this.timestamps.push(now)
    return true
  }

  getTimeUntilNext() {
    if (this.timestamps.length < this.limit) return 0
    const oldest = this.timestamps[0]
    return Math.max(0, this.window - (Date.now() - oldest))
  }
}

// Usage in useMessages hook
const rateLimiter = useRef(new RateLimiter(RATE_LIMIT_MESSAGES, RATE_LIMIT_WINDOW))

async function sendMessage(content) {
  if (!rateLimiter.current.canProceed()) {
    const wait = rateLimiter.current.getTimeUntilNext()
    return { error: `Please wait ${Math.ceil(wait / 1000)}s before sending another message` }
  }
  // ... send message
}
```

**Server-side rate limiting:** Supabase handles basic rate limiting, but for production, add Supabase Edge Functions with custom rate limiting.

### CSRF Protection
Supabase handles CSRF protection automatically via its auth system. No additional implementation needed.

### Secure Headers
If deploying to Vercel/Netlify, add security headers in config:
```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-XSS-Protection", "value": "1; mode=block" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" }
      ]
    }
  ]
}
```

---

## File Structure

```
convoak/
├── public/
│   └── favicon.ico
├── src/
│   ├── components/
│   │   ├── auth/
│   │   │   ├── AuthModal.jsx
│   │   │   ├── OtpForm.jsx
│   │   │   └── SocialButtons.jsx
│   │   ├── convo/
│   │   │   ├── ConvoView.jsx
│   │   │   ├── MessageList.jsx
│   │   │   ├── Message.jsx
│   │   │   ├── MessageInput.jsx
│   │   │   └── EmptyState.jsx
│   │   ├── landing/
│   │   │   ├── LandingPage.jsx
│   │   │   ├── SearchBar.jsx
│   │   │   └── SearchDropdown.jsx
│   │   ├── layout/
│   │   │   ├── Header.jsx
│   │   │   └── Sidebar.jsx
│   │   └── shared/
│   │       ├── Avatar.jsx
│   │       ├── Button.jsx
│   │       ├── ConvoListItem.jsx
│   │       ├── Dropdown.jsx
│   │       ├── Input.jsx
│   │       ├── Modal.jsx
│   │       └── ThemeToggle.jsx
│   ├── hooks/
│   │   ├── index.js
│   │   ├── useAuth.js
│   │   ├── useConvo.js
│   │   ├── useMessages.js
│   │   ├── useActiveConvos.js
│   │   ├── useMyConvos.js
│   │   ├── useOnlineStatus.js
│   │   └── useTheme.js
│   ├── lib/
│   │   ├── supabase.js
│   │   ├── auth.js
│   │   ├── convos.js
│   │   ├── messages.js
│   │   └── visits.js
│   ├── utils/
│   │   ├── index.js
│   │   ├── cn.js
│   │   ├── formatTimestamp.js
│   │   ├── slugify.js
│   │   ├── validation.js
│   │   └── rateLimiter.js
│   ├── pages/
│   │   ├── Landing.jsx
│   │   ├── Convo.jsx
│   │   └── AuthCallback.jsx
│   ├── App.jsx
│   ├── main.jsx
│   └── index.css
├── .env.example
├── .env.local
├── index.html
├── package.json
├── tailwind.config.js
├── postcss.config.js
└── vite.config.js
```

---

## Component Specifications

### Landing Page (`/`)

**Layout:**
- Centered content (logo + search bar)
- Full viewport height
- No sidebar, no header navigation

**SearchBar Component:**
```
Props: none
State:
  - query: string
  - isOpen: boolean (dropdown visibility)
  - selectedIndex: number (keyboard navigation)

Behavior:
  - On focus: open dropdown, fetch active convos
  - On type: filter convos, debounce 200ms
  - On Enter: navigate to /c/{slug} (create if new)
  - On Escape: close dropdown
  - On ArrowDown/Up: navigate dropdown items
  - On click outside: close dropdown
```

**SearchDropdown Component:**
```
Props:
  - convos: Convo[]
  - query: string
  - selectedIndex: number
  - onSelect: (convo: Convo) => void
  - onCreate: (topic: string) => void

Display:
  - List of matching convos (max 10)
  - Each item: topic, last activity time
  - If query doesn't match existing: show "Create: {query}" option
  - Highlight selected item
```

### Convo Page (`/c/:slug`)

**Layout:**
- Header (top)
- Sidebar (left, 280px width, collapsible on mobile)
- Chat area (main content)
- Message input (bottom of chat area)

**ConvoView Component:**
```
Props: none (uses useParams for slug)
State:
  - Managed by hooks (useConvo, useMessages)

Behavior:
  - Fetch convo by slug
  - If convo doesn't exist: show EmptyState
  - Subscribe to realtime messages
  - Track visit for authenticated users
```

**MessageList Component:**
```
Props:
  - messages: Message[]
  - loading: boolean

Behavior:
  - Scroll to bottom on mount
  - Scroll to bottom on new message
  - Show loading skeleton while fetching
```

**Message Component:**
```
Props:
  - message: {
      id: string
      content: string
      created_at: string
      user: {
        id: string
        name: string
        avatar_url: string
        is_online: boolean
      }
    }
  - isOwnMessage: boolean

Display:
  - Avatar (with online dot if online)
  - Username
  - Timestamp (formatted: "2m ago", "Yesterday", etc.)
  - Message content
  - Own messages aligned right, others aligned left
```

**MessageInput Component:**
```
Props:
  - onSend: (content: string) => Promise<void>
  - disabled: boolean

State:
  - value: string
  - sending: boolean

Behavior:
  - On Enter (without Shift): send message
  - On Shift+Enter: new line
  - Clear input after successful send
  - Show sending state (disable button, show spinner)
  - If user not authenticated: trigger auth modal on send attempt
```

**EmptyState Component:**
```
Props:
  - topic: string

Display:
  - "No messages yet"
  - "Start the conversation about {topic}"
  - Message input still visible below
```

### Header Component

```
Props:
  - convoTopic?: string (only shown on convo page)

State:
  - Managed by useAuth, useTheme hooks

Display:
  - Logo (links to /)
  - Convo topic (if on convo page)
  - Theme toggle
  - If authenticated: Avatar + dropdown (Sign out)
  - If anonymous: "Sign in" button
```

### Sidebar Component

```
Props: none
State:
  - filter: 'active' | 'my-convos'
  - Managed by useActiveConvos, useMyConvos hooks

Display (Anonymous):
  - Label: "Active Convos"
  - List of active convos

Display (Authenticated):
  - Dropdown: "Active" | "My Convos"
  - List based on selection

Mobile:
  - Hidden by default
  - Hamburger icon in header to toggle
  - Overlay when open
```

### AuthModal Component

```
Props:
  - isOpen: boolean
  - onClose: () => void
  - onSuccess: () => void

State:
  - step: 'email' | 'otp'
  - email: string
  - otp: string
  - loading: boolean
  - error: string

Display:
  - Step 1 (email):
    - Email input
    - "Continue with Email" button
    - Divider "or"
    - Google button
    - Microsoft button
  
  - Step 2 (otp):
    - "Check your email" message
    - OTP input (6 digits)
    - "Verify" button
    - "Resend code" link
    - "Back" link
```

---

## Hooks Specifications

### useAuth
```typescript
Returns {
  user: User | null
  loading: boolean
  isAuthenticated: boolean
  signInWithOtp: (email: string) => Promise<{ error?: Error }>
  verifyOtp: (email: string, token: string) => Promise<{ error?: Error }>
  signInWithGoogle: () => Promise<{ error?: Error }>
  signInWithMicrosoft: () => Promise<{ error?: Error }>
  signOut: () => Promise<{ error?: Error }>
}
```

### useConvo
```typescript
Args: slug: string
Returns {
  convo: Convo | null
  loading: boolean
  error: Error | null
  exists: boolean
}
```

### useMessages
```typescript
Args: convoId: string | null
Returns {
  messages: Message[]
  loading: boolean
  error: Error | null
  sendMessage: (userId: string, content: string) => Promise<{ data?: Message, error?: Error }>
}
```

### useActiveConvos
```typescript
Args: limit?: number (default 10)
Returns {
  convos: Convo[]
  loading: boolean
  error: Error | null
  search: (query: string) => Promise<void>
  refresh: () => Promise<void>
}
```

### useMyConvos
```typescript
Args: userId: string | null, limit?: number (default 10)
Returns {
  convos: Convo[]
  loading: boolean
  error: Error | null
  refresh: () => Promise<void>
}
```

### useTheme
```typescript
Returns {
  theme: 'light' | 'dark'
  isDark: boolean
  setTheme: (theme: 'light' | 'dark') => void
  toggleTheme: () => void
}
```

### useOnlineStatus
```typescript
Args: userId: string | null
Returns: void (side effect only - updates user's online status)
```

---

## API / Service Functions

### lib/auth.js
```javascript
signInWithOtp(email: string): Promise<{ data, error }>
verifyOtp(email: string, token: string): Promise<{ data, error }>
signInWithGoogle(): Promise<{ data, error }>
signInWithMicrosoft(): Promise<{ data, error }>
signOut(): Promise<{ error }>
getCurrentUser(): Promise<{ user, error }>
onAuthStateChange(callback): Subscription
```

### lib/convos.js
```javascript
getConvoBySlug(slug: string): Promise<{ data: Convo | null, error }>
getOrCreateConvoWithMessage(topic: string, slug: string, userId: string, content: string): Promise<{ convo: Convo, message: Message, error }>
// ^ Atomic operation: creates convo + first message in transaction (convo created on first message)
getActiveConvos(limit: number): Promise<{ data: Convo[], error }>
searchConvos(query: string, limit: number): Promise<{ data: Convo[], error }>
```

### lib/messages.js
```javascript
getMessages(convoId: string, options?: { limit?: number, before?: string }): Promise<{ data: Message[], error }>
// ^ limit defaults to 50, before is cursor (created_at of oldest message for pagination)
sendMessage(convoId: string, userId: string, content: string): Promise<{ data: Message, error }>
subscribeToMessages(convoId: string, onMessage: (msg: Message) => void): () => void
subscribeToOnlineStatus(onUpdate: (user: { id: string, is_online: boolean }) => void): () => void
```

### lib/visits.js
```javascript
trackVisit(userId: string, convoId: string): Promise<{ error }>
getMyConvos(userId: string, limit: number): Promise<{ data: Convo[], error }>
```

---

## Utils

### utils/slugify.js
```javascript
function slugify(text: string): string
// Converts topic to URL-safe slug with %2B for spaces
// "Hello World!" → "hello%2Bworld"
// "JavaScript Help" → "javascript%2Bhelp"
// "  Multiple   Spaces  " → "multiple%2Bspaces"

function displaySlug(slug: string): string
// Decodes %2B to + for UI display
// "hello%2Bworld" → "hello+world"
```

### utils/formatTimestamp.js
```javascript
function formatTimestamp(date: string | Date): string
// < 60s ago → "Just now"
// < 60m ago → "5m ago"
// < 24h ago → "3h ago"
// Yesterday → "Yesterday"
// < 7d ago → "3d ago"
// Older → "Dec 15"

function formatMessageTime(date: string | Date): string
// → "2:30 PM"
```

### utils/validation.js
```javascript
function validateMessage(content: string): { valid: boolean, error?: string, content?: string }
function validateTopic(topic: string): { valid: boolean, error?: string, topic?: string }
function validateEmail(email: string): { valid: boolean, error?: string }
```

### utils/rateLimiter.js
```javascript
class RateLimiter {
  constructor(limit: number, windowMs: number)
  canProceed(): boolean
  getTimeUntilNext(): number
}
```

### utils/cn.js
```javascript
function cn(...inputs: ClassValue[]): string
// Merges Tailwind classes, handles conflicts
```

---

## Environment Variables

**.env.example:**
```
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
```

**Supabase Dashboard Settings:**
- Enable Email OTP in Auth settings
- Configure Google OAuth (Client ID, Secret)
- Configure Microsoft OAuth (Client ID, Secret)
- Set redirect URLs for OAuth
- Configure custom SMTP (Resend) for production email delivery

---

## User Flows

### Flow 1: Anonymous User Browses
1. User lands on `/`
2. User clicks search bar → dropdown shows active convos
3. User clicks a convo → navigates to `/c/{slug}`
4. User reads messages (no auth required)
5. User browses sidebar → clicks another convo

### Flow 2: Anonymous User Sends Message
1. User is on `/c/{slug}`
2. User types message, hits Enter
3. Auth modal opens
4. User enters email → receives OTP → enters code
5. Auth succeeds → modal closes
6. Message sends automatically
7. User is now authenticated for session

### Flow 3: Creating New Convo
1. User types topic in search bar
2. No matching convo exists in dropdown
3. User clicks "Create: {topic}" or presses Enter
4. Navigates to `/c/{new-slug}` (slug uses `%2B` encoding)
5. Empty state shown: "No messages yet. Start the conversation!"
6. User types message → triggers auth modal (if anonymous)
7. **On first message send:** convo + message created atomically in single transaction
   - `getOrCreateConvoWithMessage()` handles this
   - Convo only exists in DB after first message is sent
8. User's visit is tracked, message appears in real-time

### Flow 4: Returning Authenticated User
1. User lands on `/` (already has session)
2. User clicks search bar → sees active convos
3. Navigates to `/c/{slug}`
4. Sidebar shows dropdown: "Active" | "My Convos"
5. User switches to "My Convos" → sees previously visited convos
6. User sends messages without auth prompts

---

## Error Handling

### Network Errors
```javascript
// Wrap all Supabase calls
try {
  const { data, error } = await supabaseCall()
  if (error) throw error
  return data
} catch (error) {
  // Show toast notification
  toast.error('Something went wrong. Please try again.')
  console.error(error)
}
```

### Auth Errors
- Invalid OTP: "Invalid code. Please try again."
- Expired OTP: "Code expired. Click resend to get a new one."
- OAuth failed: "Sign in failed. Please try again."

### Message Errors
- Rate limited: "Slow down! Wait {X} seconds."
- Too long: "Message too long (max 5000 characters)"
- Empty: "Message cannot be empty"
- Send failed: "Failed to send. Click to retry."

### Convo Errors
- Invalid slug: Redirect to `/` with error toast
- Load failed: Show retry button

---

## Performance Considerations

### Message Loading
- Load last 50 messages initially (ordered by `created_at DESC`, then reversed for display)
- On scroll to top: load next 50 older messages (cursor-based pagination)
- Cursor: use `created_at` of oldest loaded message
- Prevent duplicate loads with loading state

### Realtime Subscriptions
- Subscribe to current convo's messages channel
- Subscribe to users table for online status changes
- Unsubscribe when leaving convo
- Reconnect on network recovery

### Dropdown
- Debounce search input (200ms)
- Limit results to 10 items
- Cache active convos for 30 seconds

### Images
- User avatars: Use Supabase Storage or OAuth provider URLs
- Lazy load avatars outside viewport

---

## Mobile Responsiveness

### Breakpoints
- Mobile: < 768px
- Desktop: >= 768px

### Mobile Behavior
- Sidebar hidden by default, toggle via hamburger
- Sidebar opens as overlay (not push)
- Full-width search bar
- Touch-friendly tap targets (min 44px)

### Desktop Behavior
- Sidebar always visible (collapsible optional)
- Search dropdown on hover/focus

---

## Accessibility

- All interactive elements keyboard accessible
- Focus visible states
- ARIA labels on icon buttons
- Color contrast meets WCAG AA
- Screen reader announcements for new messages
- Skip to main content link

---

## Testing Checklist (Manual for MVP)

### Auth
- [ ] Email OTP sends and verifies
- [ ] Google OAuth completes
- [ ] Microsoft OAuth completes
- [ ] Sign out works
- [ ] Session persists on refresh

### Convos
- [ ] Can browse active convos (anonymous)
- [ ] Can create new convo (authenticated)
- [ ] Slug generation works correctly
- [ ] Duplicate topics go to same convo

### Messages
- [ ] Messages load on convo enter
- [ ] Can send message (authenticated)
- [ ] Real-time: new messages appear without refresh
- [ ] Messages from others appear in real-time
- [ ] Rate limiting prevents spam

### Sidebar
- [ ] Active convos load
- [ ] My Convos shows visited (authenticated)
- [ ] Dropdown switches between views
- [ ] Click navigates to convo

### Mobile
- [ ] Sidebar toggle works
- [ ] All features accessible on mobile
- [ ] No horizontal scroll

### Security
- [ ] Cannot send message without auth
- [ ] Cannot access other users' visit history
- [ ] Long messages rejected
- [ ] XSS payloads render as text

---

## Deployment

### Build
```bash
npm run build
```

### Environment
Set production environment variables:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

### Hosting Options
- **Vercel** (recommended): Zero config for Vite
- **Netlify**: Add `_redirects` file for SPA routing
- **Cloudflare Pages**: Fast edge deployment

### Post-Deploy
- Configure OAuth redirect URLs to production domain
- Test auth flows on production
- Monitor Supabase usage/limits

---

## Future Enhancements (Post-MVP)

- Typing indicators
- Message editing/deletion
- File/image uploads
- Push notifications
- User profiles
- Convo moderation tools
- "Live now" presence count per convo
- Infinite scroll for messages
- Search within convo messages
- Invite links for convos
