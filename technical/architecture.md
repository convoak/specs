# Technical Architecture

## System Overview

Convoak operates as a client-heavy web application backed by Supabase, which provides a unified platform for database operations, user authentication, and real-time message delivery. This architectural choice minimizes custom backend development by leveraging Supabase's managed services while maintaining the flexibility to implement complex business logic through PostgreSQL functions and Row Level Security policies.

The frontend communicates directly with Supabase services through its JavaScript client library, eliminating the need for a traditional API layer for most operations. The system prioritizes simplicity and developer velocity while maintaining the flexibility to scale as user adoption grows.

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

The backend infrastructure centers entirely on Supabase's suite of services built atop PostgreSQL. Rather than implementing a separate application server, business logic executes within the database through PostgreSQL functions and triggers. This approach consolidates data validation, transformation, and access control into a single layer, reducing latency and simplifying the overall system topology. Supabase's automatic API generation exposes database tables and functions as RESTful endpoints, which the frontend consumes directly with appropriate authentication headers.

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

### 2. URL Structure and Routing

Conversations are addressable through clean URLs following the pattern `/c/[slug]` where a slug derived from the topic identifies each conversation. When a user enters a topic in the search bar, the application normalizes the input into a URL-safe slug and navigates to the corresponding conversation route.

If a conversation for that topic does not yet exist, it is created on demand when the first message is sent. This routing model makes every conversation directly shareable through its URL and supports deep linking from external sources. The slug generation process applies consistent transformations to ensure that equivalent topic inputs resolve to the same conversation.

### 3. Real-time Messaging

**Responsibility:** Deliver messages instantly to all room participants

Message delivery relies on Supabase Realtime, which implements PostgreSQL's logical replication to broadcast database changes to connected clients. When a user sends a message, the insert operation triggers a publication event that Supabase Realtime captures and pushes to all clients subscribed to that conversation's channel.

This architecture ensures that message persistence and delivery are inherently synchronized—the same database write that stores the message also initiates its broadcast. Clients maintain WebSocket connections to Supabase Realtime and subscribe to specific conversation channels based on the topic they are currently viewing.

**Implementation:**

- Supabase `postgres_changes` subscription on `messages` table
- Filter: `room_id=eq.{current_room_id}`
- Client receives INSERT events and updates UI optimistically
- Message persistence handled by PostgreSQL

### 4. Authentication System

**Responsibility:** Manage user identity while preserving anonymous browsing

User authentication supports multiple pathways to accommodate different user preferences and reduce friction during signup:

- **Anonymous browsing:** No auth required to view rooms/messages
- **Authentication gate:** Required only when user attempts to send message
- **Auth methods:**
  - **Email OTP (passwordless):** Primary method allowing users to verify identity without creating or remembering a password. OTP emails delivered through Resend for reliable transactional email with high deliverability.
  - **Google OAuth:** Alternative for users who prefer social login
  - **Microsoft OAuth:** Alternative for users who prefer social login

All authentication flows are managed entirely by Supabase Auth, which handles token generation, session management, and secure credential storage. Session tokens use HTTP-only cookies with secure flag in production.

### 5. Room Management

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

### 6. User Presence

**Status:** Deferred to post-launch

**Future consideration:** Supabase Presence for "X people typing" or online indicators. Not critical for MVP.

## Frontend Architecture

The frontend is built as a single-page application using modern React patterns with a component library approach. Complex interactive primitives such as dropdowns, modals, and form controls come from shadcn/ui, which provides accessible and customizable base components. Application-specific components are built custom to maintain precise control over the user experience and avoid unnecessary abstraction layers.

The landing page presents a minimal interface dominated by the search bar, reflecting the platform's focus on immediate topic entry rather than navigation through menus or categories. A collapsible sidebar provides access to filtering options and conversation history without competing for attention with the primary search interaction.

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

## Security Architecture

Security enforcement occurs primarily at the database level through PostgreSQL Row Level Security policies. These policies define granular access rules that the database evaluates on every query, ensuring that users can only read and write data they are authorized to access regardless of how the frontend constructs its requests.

This defense-in-depth approach means that even if client-side code were compromised or bypassed, the database would reject unauthorized operations.

### Data Access

- **Row Level Security (RLS):** Enabled on all tables
- **Read access:** Public for messages/rooms (anonymous browsing)
- **Write access:** Authenticated users only
- **User data:** Private, only accessible to owner

### Rate Limiting

Rate limiting is enforced server-side at the database/API level for security (client-side can be bypassed):

- **Message sending:** PostgreSQL function enforces max messages per minute per user
- **Room creation:** Enforced via RPC function if abuse detected
- **Authentication:** Built into Supabase Auth

### Additional Security Measures

- Input sanitization to prevent cross-site scripting attacks
- Secure session handling through Supabase Auth's token management
- All communication between clients and Supabase services occurs over HTTPS with TLS encryption

## Scalability Considerations

The architecture inherits scalability characteristics from Supabase's managed infrastructure. PostgreSQL handles increasing data volumes through standard database scaling techniques, while Supabase Realtime manages WebSocket connections across distributed nodes.

The stateless nature of the frontend means that horizontal scaling of the web application is handled through Vercel, which provides global CDN distribution, automatic scaling, and optimized delivery for React applications. The platform is designed to validate its core value proposition at modest scale before investing in optimization for larger user bases.

### Current Scale (MVP)

- **Target:** 100-1000 concurrent users
- **Supabase Free Tier:** 500MB database, 2GB bandwidth, 50,000 monthly active users
- **Vercel Hobby:** Sufficient for MVP traffic

### Future Scale (Growth)

- **Database:** Upgrade to Supabase Pro ($25/mo) for 8GB + connection pooling
- **CDN:** Vercel edge network handles static assets globally
- **Real-time:** Supabase Realtime scales horizontally automatically
- **Optimization:** Implement message pagination, lazy loading, room archival

As conversation volume grows, database indexing strategies and connection pooling configurations can be tuned without architectural changes.

### Performance Targets

- **Time to first message:** < 2 seconds
- **Message delivery latency:** < 200ms
- **Search to room:** < 500ms
- **Room load time:** < 1 second

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
- **Custom logging:** Structured logging post-launch

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