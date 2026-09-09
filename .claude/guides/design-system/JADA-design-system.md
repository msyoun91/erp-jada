# JADA Design System — spec extraída

Fuente: proyecto JADA (colors_and_type.css, ui_kits/*, preview/*), extraído 2026-08-13.
**§2 Tipografía** se reescribió el 2026-09-08 desde somosjada.com, que cambió de tipografía — ese sitio es la fuente de la tipografía, no el spec original.
Ítems marcados **[EXTRAPOLADO]** no existen en el sistema fuente (que es dashboard desktop) — son decisión propia siguiendo la misma lógica visual, no del design system original. Todo lo demás es literal del spec.

**La implementación viva son los dos `globals.css`** (`erp-app/src/app/globals.css` y `erp-cliente/src/app/globals.css`): Tailwind v4, tokens en `@theme inline`, sin `tailwind.config.ts`. El snippet de config más abajo es la forma v3 del mismo spec, referencia nada más — ningún archivo del repo lo usa.

---

## 1. Colores

```
brand-50  #EBF2FD   brand-100 #C8DEFA   brand-300 #5FA3E0
brand-500 #1A6DC8   brand-700 #064379   brand-900 #011F51
gradient-brand: 140deg, #011F51 → #064379 → #1A6DC8 (solo heroes/cards destacadas, nunca fondo de texto)

neutral-50 #F5F7FB  neutral-100 #EBF0F8  neutral-300 #A5B6D0
neutral-500 #566B92 neutral-700 #2B3352  neutral-900 #0D1220

success #16A34A / bg #DCFCE7 / text #0A3B1F
warning #D97706 / bg #FEF3C7 / text #5C3200
error   #DC2626 / bg #FEE2E2 / text #5C0A0A
info    #2563EB / bg #DBEAFE / text #0C2461

bg-page #F5F7FB · bg-surface #FFFFFF · bg-subtle #EBF0F8 · bg-nav #FFFFFF
border-default rgba(13,18,32,.12) · border-strong rgba(13,18,32,.22)
```

**Dark mode: sí, first-class.** Activado con `<html data-theme="dark">` (no clase `.dark`). Pensado para modo alto-contraste/exterior (obra/sol), no solo nocturno.

```
[data-theme="dark"]
--bg-page: #070B14; --bg-surface: #0E1525; --bg-subtle: #131C30; --bg-nav: #0B1322;
--text-primary: #EDF2FF; --text-secondary: #9DB2D8; --text-tertiary: #6F86AE; --text-brand: #5FA3E0;
--border-default: rgba(255,255,255,.09); --border-strong: rgba(255,255,255,.18);
```

## 2. Tipografía

**DM Sans**, variable (100–1000), una sola familia. Self-hosted (SIL OFL) en `public/fonts/`: dos
`.woff2` partidos por `unicode-range` (latin + latin-ext) — los mismos archivos que sirve
somosjada.com — más un `@font-face` de fallback con métricas ajustadas a Arial para que el `swap` no
mueva el layout.

Reemplaza a Barlow Semi Condensed + Plus Jakarta Sans, que salieron cuando el sitio de la empresa
cambió de tipografía (ver `decisiones/global.md`). **Ya no hay familia display separada:**
`--font-sans` es la única, todo hereda de `body`, y las utilidades `font-display` / `font-body` no
existen más.

Pesos en uso: **400** cuerpo · **500** labels, botones, nav · **600** títulos. Ni el sitio ni el ERP
usan 700.

| clase | tamaño/line-height | peso | tracking | de dónde sale |
|---|---|---|---|---|
| t-display-xl | 56px/1.05 | 600 | −.022em | **[EXTRAPOLADO]** el sitio topea en 48px |
| t-display-l | 40px/1.08 | 600 | −.022em | **[EXTRAPOLADO]** ídem |
| t-h1 | 32px/1.15 | 600 | −.02em | h1 del sitio (36px, `leading-tight tracking-tight`), un escalón abajo por densidad de app |
| t-h2 | 24px/1.25 | 600 | −.015em | h2 del sitio, literal |
| t-h3 | 18px/1.35 | 600 | −.01em | h3 del sitio (16px/500), subido para que no se confunda con el cuerpo |
| t-body-l | 16px/1.6 | 400 | 0 | `text-base` del sitio |
| t-body-m | 14px/1.55 | 400 | 0 | `text-sm` del sitio, su texto secundario |
| t-label | 12px/1.2 | 500 | .12em, UPPERCASE | eyebrow del sitio (12px/500/`tracking-[0.16em]`), cerrado a .12em porque acá es label de formulario, no decoración |
| t-caption | 12px/1.45 | 400 | 0 | `text-xs` del sitio |

**El tracking de títulos es negativo, no positivo.** Barlow Semi Condensed era condensada y necesitaba
+.01/.02em para respirar; DM Sans es de ancho normal y a tamaño de título se abre sola. Arrastrar el
tracking viejo a la familia nueva dejaba los títulos desarmados. Por el mismo motivo bajan los
tamaños: al mismo px DM Sans ocupa bastante más ancho que una semi-condensada, y los títulos
empujaban el layout.

`.btn` (14px/500) y `.input` (14px) ya coincidían con los del sitio (`0.875rem`, weight 500) — no se
tocaron.

No hay escala mobile separada.

## 3. Espaciado

Base 4px — coincide con escala default de Tailwind. No extender `spacing`, usar steps nativos: 1,2,3,4,6,8,12,16,20 → 4/8/12/16/24/32/48/64/80px.

## 4. Radios y bordes

r-xs 4px (badges/code) · r-sm 6px (botones sm/pills chicos) · r-md 10px (inputs/botones/stat cards) · r-lg 16px (cards) · r-xl 24px (hero/modal/frames) · r-full (pills/avatares)
Border default 1px, inputs 1.5px, strong .22 opacity.

## 5. Sombras

```
shadow-sm 0 1px 3px rgba(13,18,32,.08)   — solo hover de card
shadow-md 0 4px 12px rgba(13,18,32,.10)
shadow-lg 0 12px 32px rgba(13,18,32,.12) — modales
```

Elevación se comunica sobre todo con bordes, no shadow. No agregar sombra a todo.

## 6. Breakpoints **[EXTRAPOLADO]**

Sistema fuente es desktop (nav 1080px max-width, sidebar fijo 168px), no define breakpoints. Propuesta: defaults de Tailwind sin tocar (sm 640 / md 768 / lg 1024 / xl 1280), sidebar de 168px colapsa a bottom-nav o drawer por debajo de `lg`.

## 7. Iconografía

Lucide (no hay set propio — está documentado como sustituto flagged en el propio README del sistema fuente). strokeWidth estándar: 1.75.

```
sidebar nav item      16px  (item con 8px×10px padding)
icon-button (header)  17-18px dentro de botón 34×34px
card feature tile     20px dentro de tile 36×36px, bg brand-50, stroke brand-700
empty state           28-32px
tabla / badge inline   14px
```

## 8. Componentes

- **Button** — primary (navy #011F51/blanco), secondary (transparente, border-strong), ghost (transparente, text-tertiary), danger (#DC2626/blanco). Sizes: sm 6px 14px/13px/r-sm, md 9px 20px/14px/r-md, lg 13px 28px. Hover: primary→#02307a, secondary→bg-subtle. **[EXTRAPOLADO]** disabled/loading: no hay spec explícito — disabled opacity:.5 cursor:not-allowed; loading = spinner reemplaza ícono izquierdo.
- **Input/Textarea** — 1.5px solid border-strong, r-md, 9px 12px, bg-surface. Focus: border brand-500 + ring 0 0 0 3px rgba(26,109,200,.12). Error: border #DC2626 + ring rgba(220,38,38,.12), texto de error debajo. **[EXTRAPOLADO]** Select: igual a Input + chevron-down a la derecha.
- **Badge** — 3px 9px, r-full, 11px/600. Variantes: brand/success/warning/error/info/neutral.
- **Modal/Dialog** — scrim rgba(7,11,20,.55), panel r-xl(24px), padding 30px, max-width 460px, shadow-lg. Título 24px/600 (t-h2). Form grid 2 columnas, 14px gap. Acciones a la derecha (secondary + primary).
- **Toast (Sonner)** — **[EXTRAPOLADO]** no hay skin custom en el spec — deriva de Alert: bg semántica clara + texto oscuro + r-md, borde 1px color semántico al 20% opacity, icon-dot 7px.
- **Tabs (ModuleTabs)** — **[EXTRAPOLADO]** no existe en el sistema. Replicar patrón jx-nav-link/jd-side-item: inactivo text-tertiary, activo text-brand-500 font-500 + underline 2px brand-500 (horizontal) o bg brand-50/text brand-700 (pill).
- **Card / list-item mobile** — Card: bg-surface, border-default, r-lg, padding 22px, hover shadow-md + translateY(-2px) (solo desktop, omitir transform en mobile). **[EXTRAPOLADO]** reemplazo de tabla en mobile: stacked list-item con tokens de jd-table row — padding 13px 20px, border-bottom 1px border-default, label t-caption/text-tertiary arriba, valor t-body-m/text-primary medium debajo, badge de estado a la derecha.
- **Empty state** — existe (jd-empty): border 1px dashed border-strong, r-lg, padding 60px, centrado, ícono 30px, título 18px/600 text-secondary (t-h3), subtítulo t-body-m.
- **Paginación** — **[EXTRAPOLADO]** no existe. Botones jx-icon-btn (34×34, r-md, border-default) para prev/next + números t-body-m, activo bg brand-50/text brand-700.
- **Sidebar nav** — ancho 168px, item 8px 10px, r-sm, 11.5px/500. Inactivo text-tertiary, hover bg-subtle+text-secondary, activo bg-brand-50+text-brand-700. Avatar circular 28px con gradient-brand-2.

## 9. Touch targets **[EXTRAPOLADO]**

Spec fuente no lo menciona (botones nativos ~32-34px de alto, sistema desktop). Para uso en obra (guantes, sol, celular): forzar mínimo 44px en todo elemento interactivo tappable en mobile (`@media (max-width: 767px)`) vía padding extra en el contenedor, sin cambiar el look visual del contenido (que puede seguir siendo 34px). No aplicar en desktop.

---

## Implementación objetivo (Tailwind v3 — revisar si cambia al scaffoldear)

`tailwind.config.ts`:

```ts
import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["selector", '[data-theme="dark"]'], // <html data-theme="dark"> — no clase .dark
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        brand: { 50: "#EBF2FD", 100: "#C8DEFA", 300: "#5FA3E0", 500: "#1A6DC8", 700: "#064379", 900: "#011F51" },
        neutral: { 50: "#F5F7FB", 100: "#EBF0F8", 300: "#A5B6D0", 500: "#566B92", 700: "#2B3352", 900: "#0D1220" },
        success: { DEFAULT: "#16A34A", bg: "#DCFCE7", text: "#0A3B1F" },
        warning: { DEFAULT: "#D97706", bg: "#FEF3C7", text: "#5C3200" },
        error:   { DEFAULT: "#DC2626", bg: "#FEE2E2", text: "#5C0A0A" },
        info:    { DEFAULT: "#2563EB", bg: "#DBEAFE", text: "#0C2461" },
        bg: { page: "var(--bg-page)", surface: "var(--bg-surface)", subtle: "var(--bg-subtle)", nav: "var(--bg-nav)" },
        text: { primary: "var(--text-primary)", secondary: "var(--text-secondary)", tertiary: "var(--text-tertiary)", brand: "var(--text-brand)", onbrand: "#FFFFFF" },
        border: { DEFAULT: "var(--border-default)", strong: "var(--border-strong)" },
      },
      backgroundImage: {
        "gradient-brand": "linear-gradient(140deg, #011F51, #064379, #1A6DC8)",
        "gradient-brand-2": "linear-gradient(140deg, #011F51, #064379)",
      },
      fontFamily: {
        sans: ["DM Sans", "DM Sans Fallback", "system-ui", "sans-serif"],
      },
      fontSize: {
        "display-xl": ["56px", { lineHeight: "1.05", letterSpacing: "-.022em", fontWeight: "600" }],
        "display-l":  ["40px", { lineHeight: "1.08", letterSpacing: "-.022em", fontWeight: "600" }],
        h1: ["32px", { lineHeight: "1.15", letterSpacing: "-.02em", fontWeight: "600" }],
        h2: ["24px", { lineHeight: "1.25", letterSpacing: "-.015em", fontWeight: "600" }],
        h3: ["18px", { lineHeight: "1.35", letterSpacing: "-.01em", fontWeight: "600" }],
        "body-l": ["16px", { lineHeight: "1.6", fontWeight: "400" }],
        "body-m": ["14px", { lineHeight: "1.55", fontWeight: "400" }],
        label: ["12px", { lineHeight: "1.2", letterSpacing: ".12em", fontWeight: "500" }],
        caption: ["12px", { lineHeight: "1.45", fontWeight: "400" }],
      },
      borderRadius: { xs: "4px", sm: "6px", md: "10px", lg: "16px", xl: "24px" },
      boxShadow: {
        sm: "0 1px 3px rgba(13,18,32,.08)",
        md: "0 4px 12px rgba(13,18,32,.10)",
        lg: "0 12px 32px rgba(13,18,32,.12)",
      },
      ringColor: { focus: "rgba(26,109,200,.12)", "focus-error": "rgba(220,38,38,.12)" },
      screens: { sm: "640px", md: "768px", lg: "1024px", xl: "1280px" }, // [EXTRAPOLADO]
    },
  },
  plugins: [],
};
export default config;
```

`globals.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@font-face { font-family: "DM Sans"; font-style: normal; font-weight: 100 1000; font-display: swap; src: url("/fonts/DMSans-latin.woff2") format("woff2"); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
@font-face { font-family: "DM Sans"; font-style: normal; font-weight: 100 1000; font-display: swap; src: url("/fonts/DMSans-latin-ext.woff2") format("woff2"); unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
@font-face { font-family: "DM Sans Fallback"; src: local("Arial"); ascent-override: 94.90%; descent-override: 29.66%; line-gap-override: 0.00%; size-adjust: 104.53%; }

:root {
  --bg-page: #F5F7FB; --bg-surface: #FFFFFF; --bg-subtle: #EBF0F8; --bg-nav: #FFFFFF;
  --text-primary: #0D1220; --text-secondary: #2B3352; --text-tertiary: #566B92; --text-brand: #1A6DC8;
  --border-default: rgba(13,18,32,.12); --border-strong: rgba(13,18,32,.22);
}
[data-theme="dark"] {
  --bg-page: #070B14; --bg-surface: #0E1525; --bg-subtle: #131C30; --bg-nav: #0B1322;
  --text-primary: #EDF2FF; --text-secondary: #9DB2D8; --text-tertiary: #6F86AE; --text-brand: #5FA3E0;
  --border-default: rgba(255,255,255,.09); --border-strong: rgba(255,255,255,.18);
}

@layer base {
  body { @apply bg-bg-page text-text-primary font-sans; -webkit-font-smoothing: antialiased; }
  a { @apply text-text-brand; }
  a:hover { @apply text-brand-500; }
}

@layer components {
  .t-display-xl { @apply text-display-xl text-text-primary; }
  .t-display-l  { @apply text-display-l text-text-primary; }
  .t-h1 { @apply text-h1 text-text-primary; }
  .t-h2 { @apply text-h2 text-text-primary; }
  .t-h3 { @apply text-h3 text-text-primary; }
  .t-body-l { @apply text-body-l text-text-secondary; }
  .t-body-m { @apply text-body-m text-text-secondary; }
  .t-label { @apply text-label uppercase text-text-tertiary; }
  .t-caption { @apply text-caption text-text-tertiary; }

  .btn { @apply inline-flex items-center gap-[7px] whitespace-nowrap rounded-md border text-sm font-medium px-5 py-[9px] transition-colors; }
  .btn-sm { @apply px-[15px] py-[7px] text-[13px] rounded-sm; }
  .btn-lg { @apply px-7 py-[13px]; }
  .btn-primary { @apply bg-brand-900 text-white border-brand-900 hover:bg-[#02307a]; }
  .btn-secondary { @apply bg-transparent text-text-primary border-border-strong hover:bg-bg-subtle; }
  .btn-ghost { @apply bg-transparent text-text-tertiary border-transparent hover:bg-bg-subtle; }
  .btn-danger { @apply bg-error text-white border-error hover:opacity-90; }
  .btn:disabled { @apply opacity-50 cursor-not-allowed; }

  .input { @apply w-full text-sm rounded-md border-[1.5px] border-border-strong bg-bg-surface text-text-primary px-3 py-[9px] outline-none; }
  .input:focus { @apply border-brand-500 ring-[3px] ring-focus; }
  .input-error { @apply border-error ring-[3px] ring-focus-error; }
  .input-error-text { @apply text-error text-xs mt-1; }

  .badge { @apply font-semibold text-[11px] rounded-full px-[9px] py-[3px]; }
  .badge-brand { @apply bg-brand-50 text-brand-900; }
  .badge-success { @apply bg-success-bg text-success-text; }
  .badge-warning { @apply bg-warning-bg text-warning-text; }
  .badge-error { @apply bg-error-bg text-error-text; }
  .badge-info { @apply bg-info-bg text-info-text; }
  .badge-neutral { @apply bg-bg-subtle text-text-tertiary; }

  .card { @apply relative bg-bg-surface border border-border rounded-lg p-[22px] transition-shadow; }
  .card:hover { @apply shadow-md; }
  .card-featured { @apply border-brand-300; }

  .empty-state { @apply bg-bg-surface border border-dashed border-border-strong rounded-lg p-[60px] text-center text-text-tertiary; }

  .nav-item { @apply flex items-center gap-[9px] rounded-sm px-[10px] py-2 text-[11.5px] font-medium text-text-tertiary cursor-pointer; }
  .nav-item:hover { @apply bg-bg-subtle text-text-secondary; }
  .nav-item-active { @apply bg-brand-50 text-brand-700; }

  @media (max-width: 767px) {
    .btn, .input, .nav-item, .icon-btn { min-height: 44px; }
  }
}
```

## Pendiente

- El snippet de `tailwind.config.ts` (forma v3) quedó como referencia muerta: ambas apps son Tailwind v4 con `@theme`. Borrarlo cuando alguien confirme que nadie lo consulta.
