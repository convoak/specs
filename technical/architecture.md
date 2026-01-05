# Technical Architecture

## Overview

Convoak uses a modern, serverless architecture optimized for real-time communication and rapid scaling. The system prioritizes simplicity and developer velocity while maintaining the flexibility to scale as user adoption grows.

## Architecture Diagram
```
┌─────────────┐
│   Client    │
│  (Next.js)  │
└──────┬──────┘
       │
       ├─────────────────────────────────┐
       │                                 │
       ▼                                 ▼
┌─────────────┐                   ┌──────────────┐
│   Vercel    │                   │  Supabase    │
│  (Hosting)  │                   │              │
└─────────────┘                   │  ┌────────┐  │
                                  │  │ Auth   │  │
                                  │  └────────┘  │
                                  │  ┌────────┐  │
                                  │  │PostgRES│  │
                                  │  └────────┘  │
                                  │  ┌────────┐  │
                                  │  │Realtime│  │
                                  │  └────────┘  │
                                  └──────────────┘
       │
       ▼
┌─────────────┐
│   Resend    │
│   (Email)   │
└─────────────┘
```

## Technology Stack

### Frontend
- **Framework:** Next.js 14+ (App Router)
- **UI Components:** shadcn/ui built on Radix UI
- **Styling:** Tailwind CSS
- **State Management:** React Context + Server Components
- **Real-time:** Supabase Realtime client

### Backend
- **Database:** Supabase PostgreSQL
- **Authentication:** Supabase Auth (Email OTP, Google OAuth, Microsoft OAuth)
- **Real-time:** Supabase Realtime (postgres_changes subscriptions)
- **API Layer:** Next.js API Routes + Supabase RPC functions

### Infrastructure
- **Hosting:** Vercel (edge network, automatic deployments)
- **Email Delivery:** Resend (transactional emails, OTP delivery)
- **DNS/Domain:** Vercel & Namecheap

## Core Components

### 1. Search & Room Discovery

**Responsibility:** Convert search queries into conversation rooms

**Flow:**
1. User enters search query
2. System normalizes query (lowercase, trim, slug generation)
3. Exact match lookup in `rooms` table
4. If exists: redirect to `/c/[slug]`
5. If not exists: create room, redirect to `/c/[slug]`

**Key Decision:** Exact matching only (no fuzzy search, no suggestions). This creates natural topic fragmentation and focused conversations.

### 2. Real-time Messaging

**Responsibility:** Deliver messages instantly to all room participants

**Implementation:**
- Supabase `postgres_changes` subscription on `messages` table
- Filter: `room_id=eq.{current_room_id}`
- Client receives INSERT events and updates UI optimistically
- Message persistence handled by PostgreSQL

**Why not WebSockets?** Supabase Realtime abstracts away connection management, reconnection logic, and scales automatically.

### 3. Authentication System

**Responsibility:** Manage user identity while preserving anonymous browsing

**Approach:**
- **Anonymous browsing:** No auth required to view rooms/messages
- **Authentication gate:** Required only when user attempts to send message
- **Auth methods:**
  - Email OTP (passwordless)
  - Google OAuth
  - Microsoft OAuth

**Session management:** Supabase handles JWT tokens, refresh logic, and secure storage.

### 4. Room Management

**Responsibility:** Create, track, and organize conversation spaces

**Data structure:**
```sql
rooms {
  id: uuid
  slug: text (unique, indexed)
  topic: text
  created_at: timestamp
  last_activity_at: timestamp
  message_count: integer
}
```

**Room lifecycle:**
- Created on-demand via search
- No deletion (archives possible in future)
- Ranked by `last_activity_at` for discovery

### 5. User Presence

**Status:** Deferred to post-launch

**Future consideration:** Supabase Presence for "X people typing" or online indicators. Not critical for MVP.

## Data Flow Examples

### Sending a Message
```
1. User types message in `/c/nature-photography`
2. Client checks auth state
   → If not authenticated: show auth modal
   → If authenticated: proceed
3. Client calls Supabase insert:
   INSERT INTO messages (room_id, user_id, content)
4. PostgreSQL triggers realtime broadcast
5. All subscribed clients receive new message
6. UI updates optimistically (message appears instantly)
```

### Joining a Conversation
```
1. User searches "artificial intelligence ethics"
2. System generates slug: "artificial-intelligence-ethics"
3. Query: SELECT * FROM rooms WHERE slug = $1
4. If found:
   → Redirect to /c/artificial-intelligence-ethics
   → Subscribe to room's message stream
5. If not found:
   → INSERT INTO rooms (slug, topic)
   → Redirect to newly created room
   → User sees empty room, can send first message
```

## Scaling Considerations

### Current Scale (MVP)
- **Target:** 100-1000 concurrent users
- **Supabase Free Tier:** 500MB database, 2GB bandwidth, 50,000 monthly active users
- **Vercel Hobby:** Sufficient for MVP traffic

### Future Scale (Growth)
- **Database:** Upgrade to Supabase Pro ($25/mo) for 8GB + connection pooling
- **CDN:** Vercel edge network handles static assets globally
- **Real-time:** Supabase Realtime scales horizontally automatically
- **Optimization:** Implement message pagination, lazy loading, room archival

### Performance Targets
- **Time to first message:** < 2 seconds
- **Message delivery latency:** < 200ms
- **Search to room:** < 500ms
- **Room load time:** < 1 second

## Security Architecture

### Authentication
- Email OTP: 6-digit code, 10-minute expiration
- OAuth: Supabase handles provider integration
- Session tokens: HTTP-only cookies, secure flag in production

### Data Access
- **Row Level Security (RLS):** Enabled on all tables
- **Read access:** Public for messages/rooms (anonymous browsing)
- **Write access:** Authenticated users only
- **User data:** Private, only accessible to owner

### Rate Limiting
- **Message sending:** [TBD - implement post-launch if abuse detected]
- **Room creation:** [TBD - may not be necessary with exact matching]
- **Authentication:** Built into Supabase Auth

## Deployment Strategy

### Environments
- **Production:** `convoak.com` (Vercel production branch)
- **Preview:** Automatic Vercel preview deployments per PR
- **Local:** `localhost:3000` with local Supabase

### CI/CD Pipeline
1. Push to GitHub
2. Vercel automatically builds and deploys
3. Supabase migrations applied via CLI or dashboard
4. Environment variables managed in Vercel dashboard

### Rollback Strategy
- Vercel: One-click rollback to previous deployment
- Database: Manual rollback via Supabase SQL editor (migrations versioned)

## Monitoring & Observability

### Metrics to Track
- **User engagement:** Messages per room, active rooms
- **Performance:** API response times, real-time latency
- **Errors:** Client-side errors, API failures
- **Growth:** New users, room creation rate

### Tools
- **Vercel Analytics:** Page views, Web Vitals
- **Supabase Dashboard:** Database queries, connection pool
- **Custom logging:** [TBD - implement structured logging post-launch]

## Technology Decisions

### Why Supabase?
- Real-time subscriptions out of the box
- PostgreSQL (proven, scalable, familiar)
- Authentication handled
- Generous free tier for MVP
- Can self-host if needed later

### Why Next.js?
- React Server Components for performance
- API routes for backend logic
- Vercel deployment integration
- Strong TypeScript support
- Large ecosystem

### Why Vercel?
- Zero-config deployments
- Edge network for global performance
- Preview deployments for every PR
- Generous free tier
- Tight Next.js integration

## Future Architectural Considerations

### Features That May Require Changes
- **Voice/video chat:** Would need WebRTC or third-party service (Agora, Daily.co)
- **File uploads:** Would need object storage (Supabase Storage or S3)
- **Search improvements:** Could add Algolia or Meilisearch for fuzzy search
- **Moderation:** May need queue system (Inngest, Trigger.dev) for content review
- **Analytics:** May add Posthog or Mixpanel for detailed user behavior

### Migration Paths
- **If Supabase limits hit:** Migrate to self-hosted Supabase or raw PostgreSQL + custom real-time
- **If Vercel costs grow:** Move to Cloudflare Pages or Railway
- **If database grows:** Implement sharding by room clusters, archive old messages

## Open Questions

- [ ] Message retention policy? (Keep forever vs archive after X months)
- [ ] Room discoverability beyond search? (Trending, recent, recommended)
- [ ] User profiles? (Display names, avatars, basic info)
- [ ] Moderation approach? (Automated, community-driven, manual review)
- [ ] Mobile apps? (React Native, or PWA sufficient?)

---

**Last Updated:** 2026-01-05  
**Status:** Specification phase  
**Next Steps:** Finalize data model, create design prototypes