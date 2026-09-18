-- sql/096 — sacar es de lo que se fue, y persona↔empresa no cambia de punta
--
-- Las dos entradas de la segunda pasada de la auditoría de compartir/transferir
-- (BACKLOG, 2026-09-18) que no piden decisión. Ninguna cambia lo que hace la UI.
--
-- 1 · `p_sacar` SE VALIDABA CONTRA LO PEDIDO, NO CONTRA LO QUE MIGRÓ. OB032
--     chequeaba `p_sacar ⊆ p_migran` antes de mover nada, pero `p_migran` se
--     filtra en silencio —solo migra lo del saliente vinculado a la obra (o a
--     la empresa)— y el resolver recibe `p_sacar` entero. Con el permiso
--     global, pasar por PostgREST el id de un contacto que no está en la obra
--     lo dejaba donde estaba y desactivaba sus vínculos en todas las demás
--     obras del saliente, también los que había sumado un tercero: quien
--     transfiere "mira y reasigna, no edita", y esto era editar.
--
--     El chequeo pasa a después de migrar y compara contra `v_personas` /
--     `v_empresas`. Reemplaza al viejo, no se le suma: lo que migró es
--     subconjunto de lo pedido, así que el nuevo implica el anterior. Por la UI
--     no cambia nada: `obras_transferir_candidatos` ofrece exactamente lo que
--     puede migrar (mismo dueño, mismo vínculo). Si algo deja de ser migrable
--     entre abrir el panel y confirmar, ahora es OB032 en vez de sacarlo sin
--     transferirlo — y el RAISE revierte lo que la función ya había movido.
--
-- 2 · `obras_persona_empresa` TENÍA `GRANT UPDATE` DE TABLA ENTERA (sql/027),
--     y la policy UPDATE solo mira la persona. El INSERT rechaza una empresa
--     que no ves (42501); el UPDATE dejaba mover `empresa_id` a esa misma, y
--     de paso tocar `id` y `created_at`. Integridad, no fuga: el dueño de esa
--     empresa no ve la fila. Se recorta a lo que describe la pertenencia —
--     `activo`, `cargo`, `es_principal`, `observaciones`—, como las otras dos
--     puentes: cambiar de persona o de empresa es otra fila, y pasa por el
--     INSERT con su chequeo. La app solo escribe `activo` por UPDATE.
--
--     REVOKE de tabla + GRANT por columna: un `REVOKE UPDATE (col)` no recorta
--     un grant de tabla entera (la trampa de sql/085).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1a · obras_transferir
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

  -- Sacar algo que no se transfiere no significa nada: sería desvincularlo de
  -- lo propio sin transferirlo, que es otra acción (desvincular, desde la
  -- ficha). Se pregunta acá y no al entrar (sql/096): `p_migran` se filtra en
  -- silencio, así que "estar en lo pedido" no era "irse", y el resolver sacaba
  -- de todas las obras del saliente algo que se quedaba donde estaba.
  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s
             WHERE NOT (s = ANY(v_personas || v_empresas))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

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
-- 1b · obras_transferir_empresa
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_transferir_empresa(
  p_empresa_id    uuid,
  p_a_usuario_id  uuid,
  p_migran        uuid[] DEFAULT '{}',
  p_sacar         uuid[] DEFAULT '{}',
  p_sacar_empresa boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_sacar    uuid[];
BEGIN
  p_migran := COALESCE(p_migran, '{}');
  p_sacar  := COALESCE(p_sacar,  '{}');

  IF NOT obras_puede_transferir('empresa', p_empresa_id) THEN
    RAISE EXCEPTION 'Sin permiso para transferir empresas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_empresas WHERE id = p_empresa_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Empresa inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La empresa ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_empresas SET creado_por = p_a_usuario_id WHERE id = p_empresa_id;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = p_empresa_id AND usuario_id = p_a_usuario_id AND activo;

  -- Acá había un cuarto UPDATE de `otorgada_por`, el de las personas ancladas
  -- en esta empresa. Mismo motivo que en `obras_transferir`: la autoridad sobre
  -- un contextual es el dueño del contacto y el del ancla, y los dos se leen de
  -- su tabla.

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND id IN (SELECT persona_id FROM obras_persona_empresa
                 WHERE empresa_id = p_empresa_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  -- Sacar es de lo que se fue: mismo corte y mismo motivo que en
  -- `obras_transferir` (sql/096). La empresa misma no viaja en `p_sacar`: su
  -- estado 3 es `p_sacar_empresa`.
  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s WHERE NOT (s = ANY(v_personas))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  -- La empresa entra a `p_sacar` del resolver si el panel eligió el estado 3
  -- para ella misma: ahí se va de las obras del saliente y suelta a sus
  -- personas que siguen siendo de él.
  v_sacar := p_sacar;
  IF p_sacar_empresa THEN
    v_sacar := v_sacar || p_empresa_id;
  END IF;

  PERFORM obras_transferir_resolver_vinculos(
    v_personas, ARRAY[p_empresa_id], v_sacar, v_actual, p_a_usuario_id, NULL
  );

  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('empresa', p_empresa_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · persona↔empresa: se edita la pertenencia, no sus puntas
-- ─────────────────────────────────────────────────────────────────────────────

REVOKE UPDATE ON public.obras_persona_empresa FROM authenticated;
GRANT UPDATE (activo, cargo, es_principal, observaciones)
  ON public.obras_persona_empresa TO authenticated;
