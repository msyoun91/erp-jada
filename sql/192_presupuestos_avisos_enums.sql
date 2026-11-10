-- Presupuestos, tramo 5, 1 de 2: los tipos de aviso. ADD VALUE va en su propia transacción: el valor no se puede usar antes del
-- commit (db_schema/notificaciones.md → Sumar un evento).

ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'presupuesto_pedido';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'presupuesto_autorizado';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'presupuesto_devuelto';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'presupuesto_a_mano';
