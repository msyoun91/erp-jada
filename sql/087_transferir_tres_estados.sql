-- ============================================================
-- 087 — Transferir: tres estados por contacto
--
-- Pedido del usuario: "cuando decido transferir una persona de una obra X mía,
-- de la obra Y mía queda desvinculado o contextual (...) puedo elegir entre
-- desvincular de todas mis obras o dejarlo como compartido contextual".
--
-- Hasta acá el checklist de transferencia tenía DOS estados: tildado (cambia de
-- dueño con la obra) o destildado (queda mío, el receptor lo ve contextual
-- dentro de esa obra). Le faltaba la mitad de atrás: qué pasa con MIS otros
-- vínculos a ese contacto cuando sí se va. Nadie contestaba esa pregunta, y el
-- default silencioso era el peor de los tres resultados posibles (abajo, §0).
--
-- Los tres estados, ahora explícitos y por contacto:
--
--   1. No se va        → queda mío; el receptor lo ve contextual en esta obra.
--                        (el destildado de siempre, sin cambios)
--   2. Se va, contextual → cambia de dueño, y me queda un grant contextual
--                        anclado a CADA obra y empresa mía que lo tiene. Lo
--                        sigo viendo donde ya lo tenía.
--   3. Se va, y lo saco → cambia de dueño, y se desactivan mis vínculos: mis
--                        obras Y mis empresas. Se va limpio.
--
-- El estado 2 es el default: es el no destructivo. `p_sacar` es el subconjunto
-- de `p_migran` que eligió el 3.
--
-- Decisiones del usuario que acotan el alcance:
--
--   a. Los vínculos que el saliente creó en obras de OTROS (sql/051,
--      `obras_obra_persona.creado_por` en una obra ajena compartida con él) NO
--      se tocan ni en el estado 3: "no lo saques, queda a decisión del nuevo
--      dueño". Matarlos vaciaría la obra de un tercero que no participó de la
--      transferencia. Siguen vivos y su `otorgada_por` pasa al receptor, que ya
--      es lo que hacían los statements de sql/084.
--
--   b. Tildar una empresa pre-tilda sus personas (decisión de UI, no de acá:
--      la función recibe la lista ya resuelta).
--
-- Y el concepto "exclusivo" se retira. `obras_contactos_exclusivos_de_*`
-- ofrecía solo lo vinculado a una única obra, ignorando `obras_persona_empresa`
-- a propósito (comentario de sql/041): de 15 personas de la base, 8 estaban en
-- una sola obra PERO con empresa, y se ofrecían como "exclusivas" sin serlo.
-- Migrar una de esas dejaba la arista persona↔empresa colgando y el contacto
-- desaparecía de la ficha de la empresa de su propio dueño. Ahora se lista
-- todo y el resumen por fila dice qué se pierde con cada estado.
--
-- Ver decisiones/obras/visibilidad.md.
-- ============================================================
BEGIN;

-- ============================================================
-- 0. El fantasma que arrastraba `obras_transferir_persona`
--
-- Hacía un solo `UPDATE obras_persona_grant_contextual SET activo = false
-- WHERE persona_id = ...` y no creaba ninguno. Resultado verificado sobre el
-- cuerpo vivo de `obras_vinculos_de_obra`: su rama `obras_es_mi_obra` deja ver
-- TODOS los vínculos de mi obra sin importar si puedo ver la entidad, así que
-- mi obra Y seguía listando el nombre de la persona transferida mientras
-- `obras_ficha_persona` me la negaba. Fila visible, ficha cerrada, sin
-- explicación. Los tres estados lo resuelven: el 2 me deja el grant, el 3 se
-- lleva la fila.
--
-- No hay backfill: los fantasmas que existan se arreglan solos la próxima vez
-- que alguien toque esos vínculos, y no hay forma de saber cuál de los dos
-- estados habría elegido quien transfirió.
-- ============================================================

-- ============================================================
-- 1. El checklist: candidatos y sus vínculos
--
-- Reemplaza a `obras_contactos_exclusivos_de_obra` / `_de_empresa`. Una fila
-- por candidato, sus vínculos adentro como jsonb: el panel necesita las dos
-- cosas a la vez y no hay razón para dos round trips.
--
-- `origen` distingue cómo llega el candidato a la obra:
--   'directo'      → `obras_obra_persona` / `obras_obra_empresa`
--   'via_empresa'  → pertenece a una empresa vinculada a la obra, sin estar
--                    vinculado a la obra él mismo. ESTOS NO EXISTÍAN en el
--                    checklist viejo y son el caso que el usuario pidió.
--
-- `vinculos` lista TODO lo activo del candidato, con `mio` = es del dueño
-- saliente. Lo que tiene `mio = false` está en obras de terceros y no se toca
-- (decisión a). Lo que tiene `mio = true` es exactamente lo que el estado 3
-- desactiva, y lo que el estado 2 devuelve como grant.
--
-- `p_tipo` sigue el vocabulario de `obras_aprobaciones.tipo`. Gate por tipo:
-- el mismo permiso que exige la transferencia correspondiente.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir_candidatos(p_tipo text, p_id uuid)
RETURNS TABLE (
  tipo           text,
  id             uuid,
  etiqueta       text,
  detalle        text,
  origen         text,
  via_empresa_id uuid,
  vinculos       jsonb
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
DECLARE
  v_duenio uuid;
BEGIN
  IF p_tipo NOT IN ('obra', 'empresa', 'persona') THEN
    RAISE EXCEPTION 'Tipo inválido para transferir' USING ERRCODE = 'OB031';
  END IF;

  IF p_tipo = 'obra' THEN
    IF NOT tiene_permiso('obras_transferir') THEN
      RAISE EXCEPTION 'Sin permiso para transferir obras' USING ERRCODE = 'OB003';
    END IF;
    SELECT responsable_id INTO v_duenio FROM obras WHERE obras.id = p_id AND activo;
    IF v_duenio IS NULL THEN
      RAISE EXCEPTION 'Obra inexistente o desactivada' USING ERRCODE = 'OB004';
    END IF;
  ELSIF p_tipo = 'empresa' THEN
    IF NOT tiene_permiso('obras_empresas_todas') THEN
      RAISE EXCEPTION 'Sin permiso para transferir empresas' USING ERRCODE = 'OB024';
    END IF;
    SELECT creado_por INTO v_duenio FROM obras_empresas WHERE obras_empresas.id = p_id AND activo;
    IF v_duenio IS NULL THEN
      RAISE EXCEPTION 'Empresa inexistente o desactivada' USING ERRCODE = 'OB025';
    END IF;
  ELSE
    IF NOT tiene_permiso('obras_personas_todas') THEN
      RAISE EXCEPTION 'Sin permiso para transferir personas' USING ERRCODE = 'OB024';
    END IF;
    SELECT creado_por INTO v_duenio FROM obras_personas WHERE obras_personas.id = p_id AND activo;
    IF v_duenio IS NULL THEN
      RAISE EXCEPTION 'Persona inexistente o desactivada' USING ERRCODE = 'OB025';
    END IF;
  END IF;

  -- Candidatos según qué se transfiere. En los tres casos se filtra por el
  -- dueño ACTUAL de la entidad, no por auth.uid(): así el admin que transfiere
  -- algo ajeno ve la misma lista que vería su dueño (criterio de sql/041).
  RETURN QUERY
  WITH candidatos AS (
    -- Transferir una obra: empresas de la obra, personas de la obra, y personas
    -- que llegan por pertenecer a una empresa de la obra.
    SELECT 'empresa'::text AS c_tipo, e.id AS c_id, e.razon_social AS c_etiqueta,
           array_to_string(oe.roles::text[], ', ') AS c_detalle,
           'directo'::text AS c_origen, NULL::uuid AS c_via
    FROM obras_obra_empresa oe
    JOIN obras_empresas e ON e.id = oe.empresa_id AND e.activo
    WHERE p_tipo = 'obra' AND oe.obra_id = p_id AND oe.activo
      AND e.creado_por = v_duenio

    UNION ALL
    SELECT 'persona', p.id, btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
           array_to_string(op.roles::text[], ', '), 'directo', NULL::uuid
    FROM obras_obra_persona op
    JOIN obras_personas p ON p.id = op.persona_id AND p.activo
    WHERE p_tipo = 'obra' AND op.obra_id = p_id AND op.activo
      AND p.creado_por = v_duenio

    UNION ALL
    -- Persona que llega solo por la empresa. El NOT EXISTS evita duplicarla
    -- cuando además está vinculada a la obra: ahí ya salió como 'directo'.
    SELECT 'persona', p.id, btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
           pe.cargo, 'via_empresa', pe.empresa_id
    FROM obras_obra_empresa oe
    JOIN obras_persona_empresa pe ON pe.empresa_id = oe.empresa_id AND pe.activo
    JOIN obras_personas p         ON p.id = pe.persona_id AND p.activo
    WHERE p_tipo = 'obra' AND oe.obra_id = p_id AND oe.activo
      AND p.creado_por = v_duenio
      AND NOT EXISTS (
        SELECT 1 FROM obras_obra_persona op2
        WHERE op2.persona_id = p.id AND op2.obra_id = p_id AND op2.activo
      )

    UNION ALL
    -- Transferir una empresa: su gente.
    SELECT 'persona', p.id, btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
           pe.cargo, 'directo', NULL::uuid
    FROM obras_persona_empresa pe
    JOIN obras_personas p ON p.id = pe.persona_id AND p.activo
    WHERE p_tipo = 'empresa' AND pe.empresa_id = p_id AND pe.activo
      AND p.creado_por = v_duenio

    -- La entidad que se transfiere entra como su propia fila cuando la elección
    -- también le cabe a ella: una persona no tiene nada colgando debajo, y una
    -- empresa puede quedar o salir de las obras del saliente. La obra no: se va
    -- entera por definición.
    UNION ALL
    SELECT 'persona', p_id, btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
           NULL::text, 'si_mismo', NULL::uuid
    FROM obras_personas p
    WHERE p_tipo = 'persona' AND p.id = p_id

    UNION ALL
    SELECT 'empresa', p_id, e.razon_social, NULL::text, 'si_mismo', NULL::uuid
    FROM obras_empresas e
    WHERE p_tipo = 'empresa' AND e.id = p_id
  ),
  unicos AS (
    -- Una persona puede llegar por dos empresas distintas de la misma obra.
    -- Se queda con una fila; `via_empresa_id` es informativo para la UI.
    SELECT DISTINCT ON (c_tipo, c_id) *
    FROM candidatos
    ORDER BY c_tipo, c_id, c_origen  -- 'directo' < 'si_mismo' < 'via_empresa'
  )
  SELECT u.c_tipo, u.c_id, u.c_etiqueta, u.c_detalle, u.c_origen, u.c_via,
         COALESCE(v.vinculos, '[]'::jsonb)
  FROM unicos u
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(x.j ORDER BY x.orden, x.etiqueta) AS vinculos
    FROM (
      -- Obras donde está el candidato. `mio` decide si el estado 3 la toca.
      SELECT 1 AS orden, o.nombre AS etiqueta,
             jsonb_build_object(
               'tipo', 'obra', 'id', o.id, 'etiqueta', o.nombre,
               'mio', o.responsable_id = v_duenio
             ) AS j
      FROM obras_obra_persona op
      JOIN obras o ON o.id = op.obra_id AND o.activo
      WHERE u.c_tipo = 'persona' AND op.persona_id = u.c_id AND op.activo

      UNION ALL
      SELECT 1, o.nombre,
             jsonb_build_object(
               'tipo', 'obra', 'id', o.id, 'etiqueta', o.nombre,
               'mio', o.responsable_id = v_duenio
             )
      FROM obras_obra_empresa oe
      JOIN obras o ON o.id = oe.obra_id AND o.activo
      WHERE u.c_tipo = 'empresa' AND oe.empresa_id = u.c_id AND oe.activo

      UNION ALL
      -- Empresas a las que pertenece. Solo aplica a personas: una empresa no
      -- cuelga de otra empresa.
      SELECT 2, e.razon_social,
             jsonb_build_object(
               'tipo', 'empresa', 'id', e.id, 'etiqueta', e.razon_social,
               'mio', e.creado_por = v_duenio
             )
      FROM obras_persona_empresa pe
      JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo
      WHERE u.c_tipo = 'persona' AND pe.persona_id = u.c_id AND pe.activo
    ) x
  ) v ON true
  ORDER BY u.c_tipo DESC, u.c_etiqueta;  -- empresas primero, después personas
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_transferir_candidatos(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_transferir_candidatos(text, uuid) TO authenticated;

-- ============================================================
-- 2. El motor de los estados 2 y 3
--
-- Lo que hace falta después de cambiar `creado_por` de un contacto, y que sirve
-- igual a las tres funciones de transferencia. Sin esto cada una repetiría los
-- mismos cuatro statements.
--
--   estado 2 (contextual): INSERT de grant hacia el saliente, anclado a cada
--     obra y empresa SUYA que tiene al contacto. Es el espejo exacto del grant
--     que sql/084 ya le daba al receptor, con los usuarios al revés.
--   estado 3 (sacar): UPDATE activo=false de los vínculos donde la otra punta
--     es del saliente. La obra ajena no se toca (decisión a).
--
-- `p_excepto_obra` deja afuera la obra que se está transfiriendo: ya no es del
-- saliente cuando esto corre, pero pasarla explícita evita depender del orden
-- de los UPDATE.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir_resolver_vinculos(
  p_personas     uuid[],
  p_empresas     uuid[],
  p_sacar        uuid[],
  p_de_usuario   uuid,
  p_a_usuario    uuid,
  p_excepto_obra uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- ---- Estado 3: sacar de lo mío ----
  UPDATE obras_obra_persona op SET activo = false, updated_at = now()
  WHERE op.persona_id = ANY(p_sacar) AND op.activo
    AND EXISTS (
      SELECT 1 FROM obras o
      WHERE o.id = op.obra_id AND o.responsable_id = p_de_usuario
        AND (p_excepto_obra IS NULL OR o.id <> p_excepto_obra)
    );

  UPDATE obras_obra_empresa oe SET activo = false, updated_at = now()
  WHERE oe.empresa_id = ANY(p_sacar) AND oe.activo
    AND EXISTS (
      SELECT 1 FROM obras o
      WHERE o.id = oe.obra_id AND o.responsable_id = p_de_usuario
        AND (p_excepto_obra IS NULL OR o.id <> p_excepto_obra)
    );

  -- La pertenencia a empresa se corta de las dos puntas: si saco a la persona,
  -- sale de MIS empresas; si saco a la empresa, salen MIS personas de ella.
  UPDATE obras_persona_empresa pe SET activo = false, updated_at = now()
  WHERE pe.activo
    AND (
      (pe.persona_id = ANY(p_sacar)
       AND EXISTS (SELECT 1 FROM obras_empresas e
                   WHERE e.id = pe.empresa_id AND e.creado_por = p_de_usuario))
      OR
      (pe.empresa_id = ANY(p_sacar)
       AND EXISTS (SELECT 1 FROM obras_personas p
                   WHERE p.id = pe.persona_id AND p.creado_por = p_de_usuario))
    );

  -- ---- Estado 2: grant recíproco hacia el saliente ----
  -- Todo lo que migró y NO está en p_sacar. Después de los UPDATE de arriba,
  -- así que los vínculos desactivados no generan grant.
  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
  SELECT DISTINCT op.persona_id, p_de_usuario, op.obra_id, p_a_usuario
  FROM obras_obra_persona op
  JOIN obras o ON o.id = op.obra_id AND o.activo AND o.responsable_id = p_de_usuario
  WHERE op.persona_id = ANY(p_personas) AND op.activo
    AND NOT (op.persona_id = ANY(p_sacar))
    AND (p_excepto_obra IS NULL OR op.obra_id <> p_excepto_obra)
  ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = p_a_usuario, updated_at = now();

  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, empresa_id, otorgada_por)
  SELECT DISTINCT pe.persona_id, p_de_usuario, pe.empresa_id, p_a_usuario
  FROM obras_persona_empresa pe
  JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo AND e.creado_por = p_de_usuario
  WHERE pe.persona_id = ANY(p_personas) AND pe.activo
    AND NOT (pe.persona_id = ANY(p_sacar))
  ON CONFLICT (persona_id, usuario_id, empresa_id) WHERE empresa_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = p_a_usuario, updated_at = now();

  -- Empresa: el ancla solo puede ser una obra. Si al saliente le quedan
  -- personas en una empresa que migró y no comparten obra, se queda viendo la
  -- razón social sin poder abrir la ficha — mismo techo que sql/070 para
  -- terceros. No se agrega ancla persona por esto.
  INSERT INTO obras_empresa_grant_contextual (empresa_id, usuario_id, obra_id, otorgada_por)
  SELECT DISTINCT oe.empresa_id, p_de_usuario, oe.obra_id, p_a_usuario
  FROM obras_obra_empresa oe
  JOIN obras o ON o.id = oe.obra_id AND o.activo AND o.responsable_id = p_de_usuario
  WHERE oe.empresa_id = ANY(p_empresas) AND oe.activo
    AND NOT (oe.empresa_id = ANY(p_sacar))
    AND (p_excepto_obra IS NULL OR oe.obra_id <> p_excepto_obra)
  ON CONFLICT (empresa_id, usuario_id, obra_id)
  DO UPDATE SET activo = true, otorgada_por = p_a_usuario, updated_at = now();
END;
$$;

-- Sin GRANT: la llaman las tres funciones de transferencia, que son DEFINER.
REVOKE EXECUTE ON FUNCTION
  public.obras_transferir_resolver_vinculos(uuid[], uuid[], uuid[], uuid, uuid, uuid) FROM PUBLIC;

-- ============================================================
-- 3. Las tres transferencias
--
-- DROP + CREATE y no OR REPLACE: cambian de aridad, así que OR REPLACE crearía
-- una sobrecarga en vez de reemplazar, y `p_contactos_exclusivos` cambia de
-- nombre — Postgres no permite renombrar parámetros con OR REPLACE. El nombre
-- viejo mentía desde que el checklist dejó de listar solo exclusivos.
-- ============================================================
DROP FUNCTION IF EXISTS obras_transferir(uuid, uuid, uuid[]);
DROP FUNCTION IF EXISTS obras_transferir_persona(uuid, uuid);
DROP FUNCTION IF EXISTS obras_transferir_empresa(uuid, uuid, uuid[]);

-- ---- 3.1 Obra ----
CREATE FUNCTION obras_transferir(
  p_obra_id      uuid,
  p_a_usuario_id uuid,
  p_migran       uuid[] DEFAULT '{}',  -- se van con la obra (estados 2 y 3)
  p_sacar        uuid[] DEFAULT '{}'   -- de esos, los que salen de lo mío (estado 3)
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_empresas uuid[];
BEGIN
  IF NOT tiene_permiso('obras_transferir') THEN
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

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras SET responsable_id = p_a_usuario_id WHERE id = p_obra_id;

  INSERT INTO obras_transferencias (tipo, obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('obra', p_obra_id, v_actual, p_a_usuario_id, auth.uid());

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
  -- anclado a esta obra. Sin cambios respecto de sql/086, salvo el nombre del
  -- parámetro.
  IF p_a_usuario_id <> auth.uid() THEN
    INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
    SELECT DISTINCT op.persona_id, p_a_usuario_id, p_obra_id, auth.uid()
    FROM obras_obra_persona op
    JOIN obras_personas p ON p.id = op.persona_id
    WHERE op.obra_id = p_obra_id AND op.activo
      AND p.creado_por = v_actual
      AND NOT (op.persona_id = ANY(p_migran))
    ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

    INSERT INTO obras_empresa_grant_contextual (empresa_id, usuario_id, obra_id, otorgada_por)
    SELECT DISTINCT oe.empresa_id, p_a_usuario_id, p_obra_id, auth.uid()
    FROM obras_obra_empresa oe
    JOIN obras_empresas e ON e.id = oe.empresa_id
    WHERE oe.obra_id = p_obra_id AND oe.activo
      AND e.creado_por = v_actual
      AND NOT (oe.empresa_id = ANY(p_migran))
    ON CONFLICT (empresa_id, usuario_id, obra_id)
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
  END IF;

  -- Nadie se comparte consigo mismo: el CHECK usuario_id <> otorgada_por lo
  -- rechazaría. La rama de persona faltaba desde sql/086 — sql/084 la tenía
  -- sobre `obras_persona_compartida`, que se dropeó sin poner el equivalente
  -- contextual, y el receptor quedaba con un grant activo sobre algo propio.
  UPDATE obras_obra_compartida SET activo = false
  WHERE obra_id = p_obra_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = ANY(v_empresas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  -- Lo compartido con terceros sigue vivo pero cuelga del nuevo dueño: quien
  -- recibe es quien ahora puede revocar. Si quedara apuntando al saliente, el
  -- acceso viviría sin nadie que pueda apagarlo. Acá entran también los
  -- vínculos que el saliente creó en obras ajenas (decisión a): no se tocan,
  -- solo cambian de otorgante.
  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND activo;

  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas));

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas)
         OR persona_id = ANY(v_personas));

  -- Y los estados 2 y 3 sobre lo que se fue.
  PERFORM obras_transferir_resolver_vinculos(
    v_personas, v_empresas, p_sacar, v_actual, p_a_usuario_id, p_obra_id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid, uuid[], uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid, uuid[], uuid[]) TO authenticated;

-- ---- 3.2 Persona ----
-- Sin candidatos debajo, pero con los mismos dos estados para ella misma:
-- `p_sacar` es un booleano acá, no una lista.
CREATE FUNCTION obras_transferir_persona(
  p_persona_id   uuid,
  p_a_usuario_id uuid,
  p_sacar        boolean DEFAULT false
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual uuid;
BEGIN
  IF NOT tiene_permiso('obras_personas_todas') THEN
    RAISE EXCEPTION 'Sin permiso para transferir personas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_personas WHERE id = p_persona_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Persona inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La persona ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_personas SET creado_por = p_a_usuario_id WHERE id = p_persona_id;

  -- Los grants que el saliente había otorgado sobre ella pasan al receptor, que
  -- es quien ahora puede revocarlos. Antes se apagaban todos, incluidos los de
  -- terceros: le sacaba el contacto a gente que no participaba.
  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = p_persona_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE persona_id = p_persona_id AND activo AND usuario_id <> p_a_usuario_id;

  PERFORM obras_transferir_resolver_vinculos(
    ARRAY[p_persona_id], '{}',
    CASE WHEN p_sacar THEN ARRAY[p_persona_id] ELSE '{}'::uuid[] END,
    v_actual, p_a_usuario_id, NULL
  );

  INSERT INTO obras_transferencias (tipo, persona_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('persona', p_persona_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_transferir_persona(uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_transferir_persona(uuid, uuid, boolean) TO authenticated;

-- ---- 3.3 Empresa ----
CREATE FUNCTION obras_transferir_empresa(
  p_empresa_id   uuid,
  p_a_usuario_id uuid,
  p_migran       uuid[] DEFAULT '{}',  -- personas de la empresa que se van
  p_sacar        uuid[] DEFAULT '{}',  -- de esas, las que salen de lo mío
  p_sacar_empresa boolean DEFAULT false -- la empresa misma sale de mis obras
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_sacar    uuid[];
BEGIN
  IF NOT tiene_permiso('obras_empresas_todas') THEN
    RAISE EXCEPTION 'Sin permiso para transferir empresas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_empresas WHERE id = p_empresa_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Empresa inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La empresa ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s WHERE NOT (s = ANY(p_migran))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_empresas SET creado_por = p_a_usuario_id WHERE id = p_empresa_id;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = p_empresa_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE empresa_id = p_empresa_id AND activo AND usuario_id <> p_a_usuario_id;

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE empresa_id = p_empresa_id AND activo AND usuario_id <> p_a_usuario_id;

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND id IN (SELECT persona_id FROM obras_persona_empresa
                 WHERE empresa_id = p_empresa_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE persona_id = ANY(v_personas) AND activo AND usuario_id <> p_a_usuario_id;

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

REVOKE EXECUTE ON FUNCTION
  public.obras_transferir_empresa(uuid, uuid, uuid[], uuid[], boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  public.obras_transferir_empresa(uuid, uuid, uuid[], uuid[], boolean) TO authenticated;

-- ============================================================
-- 4. Lo que se va
--
-- El concepto "exclusivo" se retira: el checklist ya no lista un subconjunto,
-- lista todo con su resumen.
-- ============================================================
DROP FUNCTION IF EXISTS obras_contactos_exclusivos_de_obra(uuid);
DROP FUNCTION IF EXISTS obras_contactos_exclusivos_de_empresa(uuid);

COMMIT;
