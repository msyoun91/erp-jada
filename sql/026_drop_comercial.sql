-- ============================================================
-- 026 — El módulo comercial se va entero
--
-- Revierte `sql/018_comercial.sql`. No es un archivado: el módulo deja de
-- existir, así que no aplica la regla de `activo = false` — esa regla protege
-- registros de negocio de un módulo vivo, y acá se va el módulo. Los datos que
-- había (20 filas de prueba) quedaron volcados fuera del repo antes de correr
-- esto.
--
-- **Orden.** Las tablas primero y con CASCADE: eso se lleva policies, triggers,
-- índices y FKs internas de un saque, y recién entonces las funciones quedan sin
-- dependientes. Los enums al final, cuando ya no hay columna que los use.
--
-- **`usuarios_select` se reescribe, no se dropea.** `018` la había extendido con
-- `comercial_prospectos` para que el picker de responsable viera la lista de
-- usuarios. Sacar esa cláusula es todo lo que corresponde: las otras tres
-- (perfil propio, `usuarios_ver`, las dos de tareas) son de otras migraciones y
-- siguen vigentes.
--
-- Verificado antes de correr: ninguna tabla, enum ni función fuera de comercial
-- depende de nada de acá.
-- ============================================================

-- ============================================================
-- 1. Tablas (CASCADE se lleva policies, triggers, índices y FKs)
-- ============================================================

DROP TABLE IF EXISTS comercial_comisiones CASCADE;
DROP TABLE IF EXISTS comercial_prospectos CASCADE;
DROP TABLE IF EXISTS comercial_fuentes CASCADE;
DROP TABLE IF EXISTS obra_persona CASCADE;
DROP TABLE IF EXISTS obra_empresa CASCADE;
DROP TABLE IF EXISTS obras CASCADE;
DROP TABLE IF EXISTS personas CASCADE;
DROP TABLE IF EXISTS empresas CASCADE;

-- ============================================================
-- 2. Funciones
-- ============================================================

DROP FUNCTION IF EXISTS guardar_obra_persona(uuid, uuid, uuid, uuid, rol_persona[], boolean, numeric, text);
DROP FUNCTION IF EXISTS desactivar_comision_de_relacion();
DROP FUNCTION IF EXISTS desactivar_obra_en_cascada();
DROP FUNCTION IF EXISTS validar_desactivar_empresa();
DROP FUNCTION IF EXISTS validar_desactivar_persona();
DROP FUNCTION IF EXISTS acceso_comercial();

-- ============================================================
-- 3. Enums
-- ============================================================

DROP TYPE IF EXISTS estado_prospecto;
DROP TYPE IF EXISTS rol_persona;
DROP TYPE IF EXISTS rol_empresa;
DROP TYPE IF EXISTS estado_obra;
DROP TYPE IF EXISTS tipo_obra;
DROP TYPE IF EXISTS moneda;

-- ============================================================
-- 4. Submódulos y sus asignaciones
-- ============================================================

DELETE FROM usuario_submodulos
WHERE submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'comercial');

DELETE FROM submodulos WHERE modulo = 'comercial';

-- ============================================================
-- 5. `usuarios_select` sin la cláusula de comercial
-- ============================================================

DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (
    id = auth.uid()
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('tareas_lista')
    OR tiene_permiso('tareas_proyectos')
  );
