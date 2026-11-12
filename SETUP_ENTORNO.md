# SETUP DE ENTORNO — Claude Code

Config del repo (`.claude/settings.json`, `.mcp.json`) viaja con el clone. Esto es lo que vive fuera del repo, por máquina — instalar en cada PC nueva.

## MCP — Supabase

`.mcp.json` en el repo define los servers `supabase` (ERP) y `supabase-portal` (portal), apuntados a **desarrollo**. En máquina nueva:

1. Abrir Claude Code en el repo, correr `/mcp`
2. Autenticar contra Supabase (OAuth, browser) cuando lo pida
3. Confirmar "Connected to supabase"

| | Desarrollo (`.mcp.json`, `.env.local`) | Producción |
|---|---|---|
| ERP | `tadmujaqqpwvaaxwyxlg` | `qbpudocgdvpeadcyyhfh` |
| Portal | `fuwcgqclopiahtwieffe` | `gprkjktlbtemzzjanijn` |

`.env.local` no viaja con el clone: en cada PC, URL y keys de los proyectos de desarrollo.

## Skills — caveman

Modo de respuesta comprimido (`SessionStart` hook activa "CAVEMAN MODE"). Instalado como skill standalone, no vía marketplace de plugins:

```
git clone https://github.com/JuliusBrussee/caveman.git ~/.claude/skills/caveman
```

(en Windows: `C:\Users\<usuario>\.claude\skills\caveman`)

Trae los comandos `/caveman`, `/caveman-help`, `/caveman-commit`, `/caveman-review`, `/caveman-compress` y los subagentes `cavecrew-*`.

## Pendiente / no confirmado

- `npx skills add supabase/agent-skills` — mencionado en sesión pero no verificado como instalado. Evaluar si hace falta antes de asumirlo en máquina nueva.
