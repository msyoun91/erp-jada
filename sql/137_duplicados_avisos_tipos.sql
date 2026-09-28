-- sql/137 — obras y contactos, tramo 3: los tipos de aviso de las altas
-- parecidas. En su propia transacción: `sql/139` los usa en
-- `notificaciones_listar`, que se valida al crearse.
--   alta_por_aprobar  → quienes tienen `obras_aprobar` / `contactos_aprobar`
--   alta_aprobada     → quien la cargó
--   alta_rechazada    → quien la cargó (con el motivo)
--   alta_es_la_misma  → quien la cargó
--   obra_misma_sumado → el responsable de la existente ("Pedro se sumó a…")
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'alta_por_aprobar';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'alta_aprobada';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'alta_rechazada';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'alta_es_la_misma';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obra_misma_sumado';
