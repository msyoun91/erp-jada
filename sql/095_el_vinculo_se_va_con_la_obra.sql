-- sql/095 — el vínculo se va con la obra
--
-- Segunda pasada de la auditoría de compartir/transferir (2026-09-18). El
-- `creado_por` de un vínculo obra↔persona / obra↔empresa (sql/051) dice quién
-- lo agregó, y tres reglas lo leen como autoridad: la rama `creado_por` de las
-- policies SELECT y UPDATE, el guard `OB028` (el creador es receptor de la
-- obra) y la cascada de `obras_revocar_obra` (desactiva lo del receptor). Hay
-- dos caminos que dejan un `creado_por` que ya no tiene nada que ver con la
-- obra, y los dos se probaron contra la base antes de escribir esto:
--
-- 1 · TRANSFERIR MOVÍA LA OBRA Y NO SUS VÍNCULOS. `obras_transferir` cambia
--     `responsable_id` y deja los vínculos a nombre del saliente, en los tres
--     estados del checklist: el estado 3 saca al contacto de las OTRAS obras
--     del saliente, nunca de la que se transfiere ("se fue con ella"). El
--     saliente, que ya no ve la obra, seguía leyendo las observaciones que
--     escribía el nuevo dueño, editando roles, y desactivando y reponiendo
--     vínculos por PostgREST: el dueño nuevo los quitaba y el saliente los
--     volvía a poner. Y si el nuevo dueño le compartía la obra al anterior,
--     `OB028` le trababa editar los contactos de su propia obra, y revocarlo
--     desactivaba todo lo que el anterior había cargado cuando era suya.
--
--     `obras_migrar_agenda` ya movía estos `creado_por` desde sql/088; a
--     `obras_transferir` le faltaba. Ahora los vínculos que el saliente cargó
--     en esta obra pasan al entrante, activos o no: uno inactivo que alguien
--     reactive no vuelve a nombre de quien ya no está. Los que sumó un
--     receptor siguen siendo suyos — es el diseño de sql/051, y el dueño nuevo
--     los quita si quiere.
--
-- 2 · LAS POLICIES NO PREGUNTABAN SI TODAVÍA SOS PARTE. La rama
--     `creado_por = auth.uid()` de SELECT y UPDATE vale para siempre: el
--     receptor al que le revocaron la obra (sus vínculos caen con la
--     revocación) los reponía con un `UPDATE activo = true` en una obra que ya
--     no ve. Ahora la rama exige que la obra siga compartida conmigo —la misma
--     condición que la rama de receptor de la policy INSERT—. El responsable
--     no la necesita (`obras_es_mi_obra`) y el admin lee por
--     `obras_transferir` y no edita.
--
--     El punto 1 solo, sin este, dejaba abierto al receptor revocado; este
--     solo, sin el 1, le devolvía al saliente el poder sobre sus vínculos el
--     día que el dueño nuevo le compartiera la obra.
--
-- Consecuencia asumida: `obras_es_mi_obra` exige `activo`, así que el
-- responsable de una obra desactivada deja de editar por UPDATE directo los
-- vínculos que él mismo cargó. Agregar vínculos y editar los de un receptor ya
-- estaba cerrado; queda pareja. Qué significa desactivar una obra compartida
-- es una decisión abierta (`BACKLOG.md`).
--
-- No se tocan: `obras_vinculos_de_obra` —su rama `creado_por` está detrás del
-- gate `obras_puede_ver_obra` (OB022)— ni el guard `OB028`, que con el
-- `creado_por` movido deja de dispararle al dueño nuevo sin cambiar de forma.
--
-- Exposición al aplicarla: 0 vínculos con un `creado_por` que no sea el
-- responsable ni un receptor activo de su obra. Sin backfill.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · Transferir mueve los vínculos del saliente
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_transferir(
  p_obra_id      uuid,
  p_a_usuario_id uuid,
  p_migran       uuid[] DEFAULT '{}',
  p_sacar        uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_empresas uuid[];
BEGIN
  p_migran := COALESCE(p_migran, '{}');
  p_sacar  := COALESCE(p_sacar,  '{}');

  IF NOT obras_puede_transferir('obra', p_obra_id) THEN
    RAISE EXCEPTION 'Sin permiso para transferir obras' USING ERRCODE = 'OB003';
  END IF;

  SELECT responsable_id INTO v_actual FROM obras WHERE id = p_obra_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Obra inexistente o desactivada' USING ERRCODE = 'OB004';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La obra ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  -- Sacar algo que no migra no significa nada: sería desvincularlo de lo propio
  -- sin transferirlo, que es otra acción (desvincular, desde la ficha).
  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s WHERE NOT (s = ANY(p_migran))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras SET responsable_id = p_a_usuario_id WHERE id = p_obra_id;

  INSERT INTO obras_transferencias (tipo, obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('obra', p_obra_id, v_actual, p_a_usuario_id, auth.uid());

  -- Lo que el saliente cargó en esta obra es de la obra, no de un invitado: se
  -- va con ella (sql/095). A su nombre, la rama `creado_por` de las policies le
  -- dejaba editarlo, quitarlo y reponerlo sin ver la obra, y OB028 más la
  -- cascada de `obras_revocar_obra` lo trataban como aporte de un receptor si
  -- el dueño nuevo le devolvía la obra compartida. Activos o no, como en
  -- `obras_migrar_agenda`. Lo que sumó un receptor sigue siendo suyo.
  UPDATE obras_obra_persona SET creado_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND creado_por = v_actual;

  UPDATE obras_obra_empresa SET creado_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND creado_por = v_actual;

  -- Personas que se van. El alcance se ensancha respecto de sql/086: además de
  -- las vinculadas a la obra entran las que llegan por una empresa vinculada a
  -- ella — el caso que el checklist viejo no ofrecía.
  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND (
        id IN (SELECT persona_id FROM obras_obra_persona
               WHERE obra_id = p_obra_id AND activo)
        OR id IN (SELECT pe.persona_id
                  FROM obras_persona_empresa pe
                  JOIN obras_obra_empresa oe ON oe.empresa_id = pe.empresa_id AND oe.activo
                  WHERE oe.obra_id = p_obra_id AND pe.activo)
      )
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  WITH movidas AS (
    UPDATE obras_empresas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND id IN (SELECT empresa_id FROM obras_obra_empresa
                 WHERE obra_id = p_obra_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_empresas FROM movidas;

  -- Lo que NO migra queda del saliente: grant contextual para el receptor,
  -- anclado a esta obra. El otorgante es el saliente y no `auth.uid()`: quien
  -- cede es quien otorga, el admin que ejecuta no es parte. Eso además vuelve
  -- innecesario el `IF p_a_usuario_id <> auth.uid()` que había acá — estaba
  -- para no violar el CHECK `usuario_id <> otorgada_por`, y dejaba sin
  -- contactos al admin que se transfiere la obra a sí mismo. OB005 ya garantiza
  -- que `v_actual` y el destino son distintos.
  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
  SELECT DISTINCT op.persona_id, p_a_usuario_id, p_obra_id, v_actual
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = v_actual
    AND NOT (op.persona_id = ANY(p_migran))
  ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = v_actual, updated_at = now();

  INSERT INTO obras_empresa_grant_contextual (empresa_id, usuario_id, obra_id, otorgada_por)
  SELECT DISTINCT oe.empresa_id, p_a_usuario_id, p_obra_id, v_actual
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = v_actual
    AND NOT (oe.empresa_id = ANY(p_migran))
  ON CONFLICT (empresa_id, usuario_id, obra_id)
  DO UPDATE SET activo = true, otorgada_por = v_actual, updated_at = now();

  -- Nadie se comparte consigo mismo: el CHECK usuario_id <> otorgada_por lo
  -- rechazaría.
  UPDATE obras_obra_compartida SET activo = false
  WHERE obra_id = p_obra_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = ANY(v_empresas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  -- Acá había tres UPDATE de `otorgada_por` (sql/090): lo compartido con
  -- terceros pasaba a colgar del nuevo dueño para que alguien pudiera revocarlo
  -- y para que no desapareciera de la vista Compartido. No hacen falta más. Lo
  -- que la obra comparte lo revoca y lo ve su responsable, que a partir de la
  -- línea de arriba es el receptor; lo contextual sobre contactos que no
  -- migraron lo sigue viendo y revocando su dueño, que es quien expone el
  -- teléfono. La columna queda como el log de quién otorgó, y nada la mueve.
  --
  -- Y los estados 2 y 3 sobre lo que se fue.
  PERFORM obras_transferir_resolver_vinculos(
    v_personas, v_empresas, p_sacar, v_actual, p_a_usuario_id, p_obra_id
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · "Tu vínculo" vale mientras la obra siga compartida con vos
-- ─────────────────────────────────────────────────────────────────────────────

-- SELECT: la rama `creado_por` pasa adentro de la de receptor. Las otras dos
-- no cambian.
DROP POLICY IF EXISTS obras_obra_persona_select ON obras_obra_persona;
CREATE POLICY obras_obra_persona_select ON obras_obra_persona
  FOR SELECT USING (
    obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (obras_obra_compartida_conmigo(obra_id)
        AND (creado_por = (select auth.uid())
             OR obras_ctx_vigente('persona', persona_id, 'obra', obra_id)))
  );

DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa
  FOR SELECT USING (
    obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (obras_obra_compartida_conmigo(obra_id)
        AND (creado_por = (select auth.uid())
             OR obras_ctx_vigente('empresa', empresa_id, 'obra', obra_id)))
  );

-- UPDATE: el responsable, o el receptor sobre lo suyo. La misma condición que
-- la rama de receptor de la policy INSERT (sql/051).
DROP POLICY IF EXISTS obras_obra_persona_update ON obras_obra_persona;
CREATE POLICY obras_obra_persona_update ON obras_obra_persona FOR UPDATE
  USING (tiene_permiso('obras_vincular') AND (
    obras_es_mi_obra(obra_id)
    OR (creado_por = (select auth.uid()) AND obras_obra_compartida_conmigo(obra_id))))
  WITH CHECK (tiene_permiso('obras_vincular') AND (
    obras_es_mi_obra(obra_id)
    OR (creado_por = (select auth.uid()) AND obras_obra_compartida_conmigo(obra_id))));

DROP POLICY IF EXISTS obras_obra_empresa_update ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_update ON obras_obra_empresa FOR UPDATE
  USING (tiene_permiso('obras_vincular') AND (
    obras_es_mi_obra(obra_id)
    OR (creado_por = (select auth.uid()) AND obras_obra_compartida_conmigo(obra_id))))
  WITH CHECK (tiene_permiso('obras_vincular') AND (
    obras_es_mi_obra(obra_id)
    OR (creado_por = (select auth.uid()) AND obras_obra_compartida_conmigo(obra_id))));
