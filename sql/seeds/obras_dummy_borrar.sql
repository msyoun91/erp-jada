-- ============================================================
-- Borra los datos de prueba de `obras_dummy.sql` y nada más.
--
-- DELETE de verdad y no `activo = false`: "nunca DELETE" protege filas de
-- negocio, y estas no lo son — dejarlas desactivadas ensuciaría los listados
-- con obras que nunca existieron.
--
-- El filtro es el prefijo de id, así que no puede tocar una fila real por
-- accidente. Orden de hijos a padres para no pelear con las FK.
-- ============================================================
DELETE FROM obras_accesos_persona    WHERE id::text LIKE 'a6000000-%';
DELETE FROM obras_transferencias     WHERE id::text LIKE 'a5000000-%';
DELETE FROM obras_obra_referente     WHERE id::text LIKE 'a4000000-%';
DELETE FROM obras_obra_persona       WHERE id::text LIKE 'a3000000-%';
DELETE FROM obras_obra_empresa       WHERE id::text LIKE 'a2000000-%';
DELETE FROM obras_persona_empresa    WHERE id::text LIKE 'a1000000-%';
DELETE FROM obras                    WHERE id::text LIKE 'b0000000-%';
DELETE FROM obras_personas           WHERE id::text LIKE 'c0000000-%';
DELETE FROM obras_empresas           WHERE id::text LIKE 'e0000000-%';
