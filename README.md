# README

**Search that returns people, not pages.**

Convoak is a real-time chat platform that reimagines search as a social experience. Instead of returning links, Convoak connects you with people discussing the topics you're thinking about right now.

## Vision

Organize the world's thoughts by connecting people based on shared intent, not follower graphs. Create meaningful conversations without the noise of traditional social media or the friction of hierarchical navigation.

## Core Concept

Type what you're thinking into a search interface. Get instantly placed into live conversations with strangers discussing the same topic. No feeds, no followers, just direct connection through shared curiosity.

## Current Status

**Phase:** Specification & Design  
**State:** Building comprehensive specs before implementation

This repository contains the complete specification for Convoak, including technical architecture, design system, prototypes, and functionality parameters. It serves as the single source of truth before building the production application.

## Repository Structure
```
convoak-specs/
├── technical/          # Technical architecture and implementation specs
├── design/            # Design system, prototypes, and visual specifications
├── decisions/         # Architecture Decision Records (ADRs)
└── README.md         # This file
```

## Key Differentiators

- **Intent-based matching:** Connect through what you're thinking about, not who you follow
- **Topic discovery:** No hierarchical navigation - search creates or joins conversations
- **Anonymous browsing:** Explore without commitment, authenticate only to contribute
- **Real-time first:** Live conversations, not asynchronous feeds
- **Local density:** Success measured by room activity, not platform-wide vanity metrics

## Technology Stack

- **Frontend:** Next.js, React, Tailwind CSS, shadcn/ui
- **Backend:** Supabase (PostgreSQL, real-time subscriptions, authentication)
- **Hosting:** Vercel
- **Email:** Resend

## Design Principles

- **Minimal interface:** Google-inspired simplicity
- **Typography:** Google Sans
- **Branding:** Tree ring imagery (oak cross-section)
- **Hierarchy:** Color and spacing over font weight
- **Accessibility:** Anonymous browsing with progressive authentication

## Success Metrics

- User retention within individual rooms
- Room activity and conversation quality
- Topic diversity and natural fragmentation
- Time to first meaningful interaction

## Philosophy

Embrace fragmentation as a feature. Natural conversation splitting through exact topic matching creates focused discussions rather than forcing artificial consolidation. Maintain user-centric values against platform enshittification while building toward sustainable profitability.

## Getting Started

1. Review `/technical/` for implementation specifications
2. Explore `/design/prototypes/` for visual references
3. Check `/decisions/` for architectural rationale