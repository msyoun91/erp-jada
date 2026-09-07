-- ============================================================
-- 030 — Agenda de Obras: se van cuatro campos de la ficha
--
-- `cantidad_unidades`, `superficie_estimada`, `fecha_estimada_inicio` y
-- `fecha_estimada_compra` salen de la ficha de obra por pedido del usuario.
--
-- Se dropean las columnas en vez de dejarlas ocultas en la UI: un campo que
-- ningún formulario escribe y ninguna vista muestra no es dato, es esquema
-- muerto que igual aparece en `database.types.ts` y en cada `select *`.
-- "Nunca DELETE" protege filas de negocio, no columnas que nadie llenó — la
-- tabla tiene 0 filas, así que no hay historia que perder.
--
-- No hace falta tocar el GRANT UPDATE por columna de sql/027: Postgres quita
-- la columna dropeada de los privilegios solo. Los dos CHECK (> 0) se van con
-- sus columnas. Ningún índice, trigger ni función los mencionaba.
-- ============================================================
ALTER TABLE obras
  DROP COLUMN IF EXISTS cantidad_unidades,
  DROP COLUMN IF EXISTS superficie_estimada,
  DROP COLUMN IF EXISTS fecha_estimada_inicio,
  DROP COLUMN IF EXISTS fecha_estimada_compra;
