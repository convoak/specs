# Design Prototypes

HTML prototypes serving as visual specifications for GitHub Copilot when implementing React components.

## Folder Structure

```
design/
├── assets/              # Static assets (favicons, logos)
├── components/          # Individual component references
│   ├── shared/          # Reusable components (used across pages)
│   │   ├── theme-toggle.html
│   │   ├── sign-in-button.html
│   │   ├── user-avatar.html
│   │   └── hamburger-menu.html
│   ├── landing/         # Landing page-specific components
│   │   └── header.html  # Layout component (assembles shared components)
│   └── chat-room/       # Chat room page-specific components
└── prototypes/          # Full page compositions
    ├── landing.html
    └── chat-room.html
```

## Component Types

### Shared Components (`components/shared/`)
Atomic, reusable UI elements used across multiple pages:
- Each file is a **standalone HTML page** showing the component in isolation
- Includes all states/variants with interactive demos
- Maps 1:1 to a React component in the production app

### Layout Components (`components/<page>/`)
Page-specific components that compose shared components:
- Example: `landing/header.html` arranges theme-toggle, sign-in-button, user-avatar, and hamburger-menu
- Shows spatial relationships and responsive breakpoints
- Comments mark where each shared component slots in

### Prototypes (`prototypes/`)
Full page assemblies showing the complete UI:
- Use these to understand overall page structure and flow
- Combines multiple layout components into a complete view

## Conventions

1. **Standalone files**: Each HTML file includes its own Tailwind config, CSS variables, and scripts. This allows viewing any file in isolation without dependencies.

2. **Tailwind + shadcn/ui**: All components use the shadcn-zinc color palette and shadcn/ui styling patterns. The Tailwind config in any file is canonical.

3. **Comments for Copilot**: Component files include HTML comments explaining:
   - What the component does
   - How it maps to React
   - State management notes
   - Accessibility considerations

4. **Interactive demos**: Components include buttons/toggles to demonstrate different states (hover, disabled, dark mode, etc.)

## For Copilot

When implementing a React component:
1. Find the corresponding HTML file in `components/`
2. Read the component comments for implementation notes
3. Translate the HTML/Tailwind to React + shadcn/ui components
4. Preserve the exact styling and behavior demonstrated

When implementing a full page:
1. Check `prototypes/` for the page layout
2. Reference individual components in `components/` for details
3. Compose React components following the same structure
