-- Catálogo, tramo 7, 1 de 2: los tipos de aviso. ADD VALUE va en su propia transacción: el valor no se puede usar antes del
-- commit (db_schema/notificaciones.md → Sumar un evento).

ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_insumo_sin_costo';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_categoria_nueva';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_baja';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_porcentaje_cambiado';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_porcentaje_revertido';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_version_enviada';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_version_aprobada';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'catalogo_version_devuelta';
