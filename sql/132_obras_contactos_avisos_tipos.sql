-- sql/132 — obras y contactos: tipos de campanita (tramo 2).
--
-- En su propia transacción: un valor nuevo no se usa antes del commit, y
-- `sql/134` lo castea en `notificaciones_listar`.
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obra_transferida';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obra_sumado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obra_quitado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obras_recibidas';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obras_huerfanas';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'persona_transferida';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'agenda_recibida';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'personas_huerfanas';
