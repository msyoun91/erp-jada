-- Visibilidad del módulo tareas: ser creador deja de dar acceso.
--
-- Regla (pedido de usuario): sin `tareas_gestionar_ajenas` solo se ve lo
-- asignado y lo público. Si te sacan la asignación dejás de ver la tarea — y
-- el hilo/proyecto donde vivía — aunque la hayas creado. Única excepción:
-- `tareas_hilos.responsable_id`, el dueño del hilo, que no es una asignación.
--
-- Segundo cambio: la membresía de proyecto pasa a ser su propia función
-- (`tareas_proyectos_miembros`), separada de "editar el proyecto".
--
-- Reemplaza definiciones de sql/005, sql/008 y sql/009. Si alguna vez se
-- re-corre el repo entero desde 001, este archivo va último.

-- ============================================================
-- 1. Visibilidad de hilos — sin creado_por
-- ============================================================
CREATE OR REPLACE FUNCTION puede_ver_hilo(p_hilo_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    tiene_permiso('tareas_gestionar_ajenas')
    OR h.responsable_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM tareas t
      JOIN tareas_asignados ta ON ta.tarea_id = t.id AND ta.activo
      WHERE t.hilo_id = h.id AND ta.usuario_id = auth.uid()
    )
    OR (
      h.proyecto_id IS NOT NULL AND h.visibilidad = 'publico'
      AND (
        (SELECT pr.visibilidad FROM tareas_proyectos pr WHERE pr.id = h.proyecto_id) = 'publico'
        OR es_miembro_proyecto(h.proyecto_id, auth.uid())
      )
    )
  FROM tareas_hilos h
  WHERE h.id = p_hilo_id;
$$;

-- ============================================================
-- 2. Visibilidad de tareas — asignación activa, o público
-- ============================================================
-- La tarea suelta sin proyecto y pública pasa a verse: antes la tapaba la
-- rama del creador, y sin ella no la vería nadie.
DROP POLICY IF EXISTS tareas_select ON tareas;
CREATE POLICY tareas_select ON tareas FOR SELECT
  USING (
    tiene_permiso('tareas_gestionar_ajenas')
    OR EXISTS (
      SELECT 1 FROM tareas_asignados ta
      WHERE ta.tarea_id = tareas.id AND ta.usuario_id = auth.uid() AND ta.activo
    )
    OR (hilo_id IS NOT NULL AND puede_ver_hilo(hilo_id))
    OR (
      hilo_id IS NULL AND visibilidad = 'publico'
      AND (
        proyecto_id IS NULL
        OR (SELECT pr.visibilidad FROM tareas_proyectos pr WHERE pr.id = tareas.proyecto_id) = 'publico'
        OR es_miembro_proyecto(proyecto_id, auth.uid())
      )
    )
  );

-- UPDATE alineado con SELECT: nadie modifica lo que no ve. El responsable del
-- hilo entra explícito porque "deshacer conversión" y el cierre de un hilo
-- tocan tareas a las que no está asignado — sin esa rama el UPDATE no falla,
-- afecta 0 filas en silencio.
DROP POLICY IF EXISTS tareas_update ON tareas;
CREATE POLICY tareas_update ON tareas FOR UPDATE
  USING (
    tiene_permiso('tareas_gestionar_ajenas')
    OR responsable_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM tareas_asignados ta
      WHERE ta.tarea_id = tareas.id AND ta.usuario_id = auth.uid() AND ta.activo
    )
    OR EXISTS (
      SELECT 1 FROM tareas_hilos h
      WHERE h.id = tareas.hilo_id AND h.responsable_id = auth.uid()
    )
  )
  WITH CHECK (
    (
      tiene_permiso('tareas_gestionar_ajenas')
      OR responsable_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM tareas_asignados ta
        WHERE ta.tarea_id = tareas.id AND ta.usuario_id = auth.uid() AND ta.activo
      )
      OR EXISTS (
        SELECT 1 FROM tareas_hilos h
        WHERE h.id = tareas.hilo_id AND h.responsable_id = auth.uid()
      )
    )
    AND (
      estado <> 'completada'
      OR modo_completado = 'manual'
      OR responsable_id = auth.uid()
      OR tiene_permiso('tareas_gestionar_ajenas')
    )
  );

-- ============================================================
-- 3. Hilos y proyectos — el creador deja de ser un actor
-- ============================================================
DROP POLICY IF EXISTS tareas_hilos_update ON tareas_hilos;
CREATE POLICY tareas_hilos_update ON tareas_hilos FOR UPDATE
  USING (responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  WITH CHECK (responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'));

DROP POLICY IF EXISTS tareas_hilos_notas_insert ON tareas_hilos_notas;
CREATE POLICY tareas_hilos_notas_insert ON tareas_hilos_notas FOR INSERT
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM tareas_hilos h
      WHERE h.id = tareas_hilos_notas.hilo_id
        AND (h.responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
    )
  );

DROP POLICY IF EXISTS tareas_proyectos_select ON tareas_proyectos;
CREATE POLICY tareas_proyectos_select ON tareas_proyectos FOR SELECT
  USING (
    visibilidad = 'publico'
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_miembro_proyecto(id, auth.uid())
  );

-- Editar sigue siendo del creador, pero solo mientras sea miembro: si se sacó
-- a sí mismo del proyecto ya no lo ve, y modificar lo que no se ve es el
-- estado inconsistente que este archivo cierra.
DROP POLICY IF EXISTS tareas_proyectos_update ON tareas_proyectos;
CREATE POLICY tareas_proyectos_update ON tareas_proyectos FOR UPDATE
  USING (
    (creado_por = auth.uid() AND es_miembro_proyecto(id, auth.uid()))
    OR tiene_permiso('tareas_gestionar_ajenas')
  )
  WITH CHECK (
    (creado_por = auth.uid() AND es_miembro_proyecto(id, auth.uid()))
    OR tiene_permiso('tareas_gestionar_ajenas')
  );

-- ============================================================
-- 4. es_responsable_tarea — reemplaza es_responsable_o_creador_tarea
-- ============================================================
-- Sin esto el creador se re-agrega a `tareas_asignados` por API y recupera la
-- visibilidad que este archivo le quita. No hace falta la rama del creador:
-- `tareas_insert` ya exige responsable_id = auth.uid() a quien no tiene
-- gestionar_ajenas, así que al crear la tarea siempre puede insertar sus
-- asignados. SECURITY DEFINER por el mismo motivo que la función vieja
-- (romper la recursión tareas <-> tareas_asignados).
CREATE OR REPLACE FUNCTION es_responsable_tarea(p_tarea_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas t
    WHERE t.id = p_tarea_id AND t.responsable_id = auth.uid()
  );
$$;

DROP POLICY IF EXISTS tareas_asignados_select ON tareas_asignados;
CREATE POLICY tareas_asignados_select ON tareas_asignados FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_tarea(tarea_id)
    OR es_asignado_tarea(tarea_id)
  );

DROP POLICY IF EXISTS tareas_asignados_insert ON tareas_asignados;
CREATE POLICY tareas_asignados_insert ON tareas_asignados FOR INSERT
  WITH CHECK (
    (tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_tarea(tarea_id))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

-- `usuario_id = auth.uid()` en el WITH CHECK queda acotado a NOT activo:
-- sacarme de una tarea sigue siendo mío, re-agregarme no. Sin ese recorte, a
-- quien le quitaron la asignación se la devuelve él mismo por API y recupera
-- la visibilidad que este archivo le saca.
DROP POLICY IF EXISTS tareas_asignados_update ON tareas_asignados;
CREATE POLICY tareas_asignados_update ON tareas_asignados FOR UPDATE
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_tarea(tarea_id)
  )
  WITH CHECK (
    (
      (usuario_id = auth.uid() AND NOT activo)
      OR tiene_permiso('tareas_gestionar_ajenas')
      OR es_responsable_tarea(tarea_id)
    )
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

DROP POLICY IF EXISTS tareas_notas_insert ON tareas_notas;
CREATE POLICY tareas_notas_insert ON tareas_notas FOR INSERT
  WITH CHECK (
    usuario_id = auth.uid()
    AND (
      tiene_permiso('tareas_gestionar_ajenas')
      OR es_responsable_tarea(tarea_id)
      OR es_asignado_tarea(tarea_id)
    )
  );

DROP FUNCTION IF EXISTS es_responsable_o_creador_tarea(uuid);

-- ============================================================
-- 5. Membresía de proyecto = función propia
-- ============================================================
-- Alta y baja de miembros dejan de derivar de "creaste el proyecto": son la
-- función `tareas_proyectos_miembros`. La excepción es la siembra inicial —
-- todo proyecto exige al menos un miembro (sql/009), así que sin esta rama
-- `tareas_proyectos_crear` no alcanzaría para crear nada. Queda acotada al
-- proyecto que todavía no tiene miembros: una vez creado, cambiar quién
-- trabaja en él exige la función.
CREATE OR REPLACE FUNCTION proyecto_tiene_miembros(p_proyecto_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas_proyectos_miembros m
    WHERE m.proyecto_id = p_proyecto_id AND m.activo
  );
$$;

-- El SELECT NO mira la función: ver la membresía sigue siendo de miembros y
-- managers. Agregarla ahí filtraba los miembros de proyectos que el usuario
-- ni siquiera ve, y no hacía falta — para editar un proyecto ya hay que ser
-- creador-y-miembro (o ajenas), así que quien usa la función entra por
-- es_miembro_proyecto.
DROP POLICY IF EXISTS tareas_proyectos_miembros_select ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_select ON tareas_proyectos_miembros FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_miembro_proyecto(proyecto_id, auth.uid())
  );

DROP POLICY IF EXISTS tareas_proyectos_miembros_insert ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_insert ON tareas_proyectos_miembros FOR INSERT
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR tiene_permiso('tareas_proyectos_miembros')
    OR (es_creador_proyecto(proyecto_id) AND NOT proyecto_tiene_miembros(proyecto_id))
  );

DROP POLICY IF EXISTS tareas_proyectos_miembros_update ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_update ON tareas_proyectos_miembros FOR UPDATE
  USING (
    tiene_permiso('tareas_gestionar_ajenas')
    OR tiene_permiso('tareas_proyectos_miembros')
  )
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR tiene_permiso('tareas_proyectos_miembros')
  );

-- ============================================================
-- 6. GRANTs — mismo criterio que sql/006
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.es_responsable_tarea(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_responsable_tarea(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.proyecto_tiene_miembros(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.proyecto_tiene_miembros(uuid) TO authenticated;

-- ============================================================
-- 7. Seed — nueva función del módulo
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_proyectos_miembros', 'tareas', 'funcion', 'Asignar miembros', id, 2
FROM submodulos WHERE codigo = 'tareas_proyectos'
ON CONFLICT DO NOTHING;

-- Los creadores de proyectos existentes ya administraban miembros: se les
-- conserva la capacidad para no romper proyectos en curso. Alta manual desde
-- Usuarios para el resto.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT DISTINCT p.creado_por, s.id
FROM tareas_proyectos p
CROSS JOIN submodulos s
WHERE s.codigo = 'tareas_proyectos_miembros'
  AND p.activo
ON CONFLICT DO NOTHING;
