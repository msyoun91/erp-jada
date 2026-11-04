-- Catálogo: un INSERT directo no puede inventar por qué un paquete está de baja (AUDITORIA_CATALOGO.md, hallazgo 10).
-- Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_ciclo.sql.

-- El GRANT por tabla de sql/160 alcanzaba a las baja_* que sumó sql/162. Se deja activo porque el DEFAULT VALUES de
-- catalogo_paquete_alta y catalogo_paquete_duplicar necesita INSERT sobre alguna columna.
REVOKE INSERT ON public.catalogo_paquetes FROM authenticated;
GRANT INSERT (activo) ON public.catalogo_paquetes TO authenticated;
