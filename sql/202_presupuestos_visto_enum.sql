-- Portal, tramo 3, 1 de 2: el aviso de la primera visita. ADD VALUE va en su propia transacción: el valor no se puede usar antes
-- del commit. Decisiones: decisiones/erp-cliente.md → Visitas.
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'presupuesto_visto';
