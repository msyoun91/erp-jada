-- ============================================================
-- 086 — La obra es el único acto de compartir
--
-- Pedido del usuario: "yo no quiero compartir empresas, yo solo quiero mostrar
-- los que están involucrados en la obra mediante contexto, y antes de compartir
-- pasa por un proceso de checklist de quiénes voy a mostrar a cada usuario".
--
-- Eso ya es `obras_compartir_obra(obra, usuario, empresas[], personas[])` desde
-- sql/082 + sql/085: el checklist es por usuario, lo tildado va a grant
-- contextual anclado a esa obra, lo destildado se apaga (estado deseado,
-- sql/049). Lo que faltaba era cerrar la segunda puerta: el share DIRECTO de
-- persona y empresa desde su propia ficha, que da acceso completo y mete la
-- entidad en la agenda del receptor.
--
-- Después de esta migración hay un solo camino: **compartís una obra y elegís
-- en el checklist qué empresas y personas de esa obra ve ese usuario, dentro de
-- esa obra**. La agenda de cada uno vuelve a ser estrictamente lo suyo.
--
-- Corte limpio, sin backfill: al escribirla había 0 grants directos activos
-- (3 personas + 1 empresa, todas ya revocadas). El paso 1 los apaga igual, por
-- si aparece alguno entre hoy y el día que se aplique.
--
-- Lo que se pierde, asumido: colgar un contacto ajeno de una obra propia (la
-- rama `obras_*_grant_directo` de sql/052). El contextual nunca lo habilitó.
-- Quedan `obras_personas_todas` / `obras_empresas_todas` y transferir.
--
-- APLICADA el 2026-09-17, partida en tres migraciones remotas por tamaño:
-- 086a_solo_la_obra_comparte_policies (pasos 1-3), 086b_..._definers (paso 4),
-- 086c_..._drops (pasos 4b-5). Este archivo es el contenido completo y en orden.
--
-- Ver decisiones/obras/visibilidad.md.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Corte: nada queda vivo en las dos tablas de share directo
-- ============================================================
UPDATE obras_persona_compartida SET activo = false, updated_at = now() WHERE activo;
UPDATE obras_empresa_compartida SET activo = false, updated_at = now() WHERE activo;

-- ============================================================
-- 2. Policies — sale la rama de grant completo
--
-- Las cuatro dependen de `obras_*_compartida_conmigo` / `obras_*_grant_directo`,
-- que se dropean en el paso 5: van primero.
--
-- `obras_obra_persona_select` además gana la rama contextual anclada que
-- `sql/082` le puso a su gemela de empresa y a ella no. Sin share directo, el
-- receptor no podía leer la fila de vínculo (la ficha igual la mostraba: sale
-- por `obras_vinculos_de_obra`, DEFINER). Misma forma en las dos.
--
-- `obras_personas_select` no se toca: su rama de grant completo está adentro de
-- `obras_puede_ver_persona`, que se reescribe en el paso 3.
-- ============================================================
DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas
FOR SELECT USING (
  (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
  AND (
    creado_por = (SELECT auth.uid())
    OR (pendiente AND tiene_permiso('obras_aprobar'))
    OR (
      NOT pendiente
      AND (
        tiene_permiso('obras_empresas_todas')
        OR obras_empresa_grant_ctx_vigente(id)
      )
    )
  )
);

DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa
FOR SELECT USING (
  creado_por = (SELECT auth.uid())
  OR obras_es_mi_obra(obra_id)
  OR tiene_permiso('obras_transferir')
  OR (
    obras_obra_compartida_conmigo(obra_id)
    AND obras_empresa_grant_ctx_obra_conmigo(empresa_id, obra_id)
  )
);

DROP POLICY IF EXISTS obras_obra_persona_select ON obras_obra_persona;
CREATE POLICY obras_obra_persona_select ON obras_obra_persona
FOR SELECT USING (
  creado_por = auth.uid()
  OR obras_es_mi_obra(obra_id)
  OR tiene_permiso('obras_transferir')
  OR (
    obras_obra_compartida_conmigo(obra_id)
    AND obras_persona_grant_ctx_obra_conmigo(persona_id, obra_id)
  )
);

DROP POLICY IF EXISTS obras_obra_empresa_insert ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_insert ON obras_obra_empresa
FOR INSERT WITH CHECK (
  tiene_permiso('obras_vincular')
  AND obras_puede_ver_empresa(empresa_id)
  AND (
    (
      obras_es_mi_obra(obra_id)
      AND (
        EXISTS (
          SELECT 1 FROM obras_empresas e
          WHERE e.id = obras_obra_empresa.empresa_id AND e.creado_por = auth.uid()
        )
        OR tiene_permiso('obras_empresas_todas')
      )
    )
    OR (
      obras_obra_compartida_conmigo(obra_id)
      AND EXISTS (
        SELECT 1 FROM obras_empresas e
        WHERE e.id = obras_obra_empresa.empresa_id AND e.creado_por = auth.uid()
      )
    )
  )
);

DROP POLICY IF EXISTS obras_obra_persona_insert ON obras_obra_persona;
CREATE POLICY obras_obra_persona_insert ON obras_obra_persona
FOR INSERT WITH CHECK (
  tiene_permiso('obras_vincular')
  AND obras_puede_ver_persona(persona_id)
  AND (
    (
      obras_es_mi_obra(obra_id)
      AND (
        EXISTS (
          SELECT 1 FROM obras_personas p
          WHERE p.id = obras_obra_persona.persona_id AND p.creado_por = auth.uid()
        )
        OR tiene_permiso('obras_personas_todas')
      )
    )
    OR (
      obras_obra_compartida_conmigo(obra_id)
      AND EXISTS (
        SELECT 1 FROM obras_personas p
        WHERE p.id = obras_obra_persona.persona_id AND p.creado_por = auth.uid()
      )
    )
  )
);

-- ============================================================
-- 3. Visibilidad — dueño o `_todas`, nada más
--
-- `obras_puede_ver_*` vuelve a lo que era antes de que existiera el share
-- directo. El contextual no entra acá a propósito: no es "ver la entidad", es
-- "ver la entidad dentro de esta obra", y eso lo resuelven
-- `obras_*_grant_ctx_*` y las funciones de ficha.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_ver_persona_de(p_persona_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT (usuario_tiene_permiso(p_usuario, 'obras_ver') OR usuario_tiene_permiso(p_usuario, 'obras_personas'))
    AND EXISTS (
      SELECT 1 FROM obras_personas p
      WHERE p.id = p_persona_id
        AND (
          p.creado_por = p_usuario
          OR (NOT p.pendiente AND usuario_tiene_permiso(p_usuario, 'obras_personas_todas'))
        )
    );
$$;

CREATE OR REPLACE FUNCTION obras_puede_ver_empresa_de(p_empresa_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT (usuario_tiene_permiso(p_usuario, 'obras_ver') OR usuario_tiene_permiso(p_usuario, 'obras_empresas'))
    AND EXISTS (
      SELECT 1 FROM obras_empresas e
      WHERE e.id = p_empresa_id AND e.activo
        AND (
          e.creado_por = p_usuario
          OR (NOT e.pendiente AND usuario_tiene_permiso(p_usuario, 'obras_empresas_todas'))
        )
    );
$$;

-- ============================================================
-- 4. Las DEFINER que leían las dos tablas
-- ============================================================

-- `obras_vinculos_de_obra` (sql/051/070/082/085): la rama del receptor queda
-- solo contextual y anclada.
CREATE OR REPLACE FUNCTION obras_vinculos_de_obra(p_obra_id uuid)
RETURNS TABLE (
  tipo          text,
  vinculo_id    uuid,
  entidad_id    uuid,
  nombre        text,
  detalle       text,
  roles         text[],
  observaciones text,
  empresa_id    uuid,
  creado_por    uuid,
  creado_por_nombre text,
  es_de_receptor    boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT obras_puede_ver_obra(p_obra_id) THEN
    RAISE EXCEPTION 'Sin acceso a esta obra' USING ERRCODE = 'OB022';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, oe.id, e.id, e.razon_social, NULL::text,
         oe.roles::text[], oe.observaciones, NULL::uuid,
         oe.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, oe.creado_por)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  JOIN usuarios u       ON u.id = oe.creado_por
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND (
      oe.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_empresa_grant_ctx_obra_conmigo(oe.empresa_id, p_obra_id))
    )

  UNION ALL
  SELECT 'persona'::text, op.id, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         CASE WHEN vis.empresa_visible THEN e2.razon_social END,
         op.roles::text[], op.observaciones, op.empresa_id,
         op.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, op.creado_por)
  FROM obras_obra_persona op
  JOIN obras_personas p       ON p.id = op.persona_id
  JOIN usuarios u             ON u.id = op.creado_por
  LEFT JOIN obras_empresas e2 ON e2.id = op.empresa_id
  CROSS JOIN LATERAL (
    SELECT op.empresa_id IS NOT NULL
       AND (obras_es_mi_obra(p_obra_id)
            OR tiene_permiso('obras_transferir')
            OR obras_puede_ver_empresa(op.empresa_id)
            OR obras_empresa_grant_ctx_obra_conmigo(op.empresa_id, p_obra_id)) AS empresa_visible
  ) vis
  WHERE op.obra_id = p_obra_id AND op.activo
    AND (
      op.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_persona_grant_ctx_obra_conmigo(op.persona_id, p_obra_id))
    );
END;
$$;

-- `obras_relaciones_compartibles_obra` (sql/047/048): `ya_compartida` mira solo
-- el grant contextual de esta obra. La trampa de sql/048 sigue vigente: toda
-- columna con nombre de campo de salida va calificada.
CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_obra(p_obra_id uuid, p_usuario_id uuid)
RETURNS TABLE (
  tipo          text,
  id            uuid,
  etiqueta      text,
  detalle       text,
  ya_compartida boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid() AND o.activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, e.id, e.razon_social,
         nullif(array_to_string(oe.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_empresa_grant_contextual g
                 WHERE g.empresa_id = e.id AND g.usuario_id = p_usuario_id
                   AND g.obra_id = p_obra_id AND g.activo)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
  UNION ALL
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(array_to_string(op.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_persona_grant_contextual g
                 WHERE g.persona_id = p.id AND g.usuario_id = p_usuario_id
                   AND g.obra_id = p_obra_id AND g.activo)
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;

-- `obras_compartidos_por_mi` (sql/047/050/082/085): 5 UNION → 3. Todo lo que
-- queda cuelga de una obra, así que la vista Compartido es un árbol de un solo
-- nivel: obra → lo que le tildé a cada usuario.
CREATE OR REPLACE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE (
  tipo           text,
  entidad_id     uuid,
  entidad_nombre text,
  usuario_id     uuid,
  usuario_nombre text,
  origen_tipo    text,
  origen_id      uuid,
  origen_nombre  text,
  compartida_el  timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'empresa'::text, g.empresa_id, e.razon_social, g.usuario_id, u.nombre,
         'obra'::text, g.obra_id,
         (SELECT nombre FROM obras WHERE id = g.obra_id),
         g.created_at
  FROM obras_empresa_grant_contextual g
  JOIN obras_empresas e ON e.id = g.empresa_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.otorgada_por = auth.uid() AND g.activo

  UNION ALL
  SELECT 'persona'::text, g.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         g.usuario_id, u.nombre,
         CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
         coalesce(g.obra_id, g.empresa_id),
         CASE WHEN g.obra_id IS NOT NULL
              THEN (SELECT nombre FROM obras WHERE id = g.obra_id)
              ELSE (SELECT razon_social FROM obras_empresas WHERE id = g.empresa_id) END,
         g.created_at
  FROM obras_persona_grant_contextual g
  JOIN obras_personas p ON p.id = g.persona_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.otorgada_por = auth.uid() AND g.activo

  ORDER BY 9 DESC
  LIMIT 500;
END;
$$;

-- `obras_puede_ver_compartido` (sql/083): solo la obra emite eventos de
-- compartir, así que solo la obra tiene evento que mostrar. Los eventos viejos
-- de persona/empresa quedan en `eventos` sin lector — son 4 y ya están
-- revocados.
CREATE OR REPLACE FUNCTION obras_puede_ver_compartido(p_tipo text, p_id uuid, p_usuario_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public
AS $$
  SELECT p_tipo = 'obra' AND EXISTS (
    SELECT 1 FROM obras_obra_compartida g
    WHERE g.obra_id = p_id AND g.usuario_id = p_usuario_id
  );
$$;

-- `obras_transferir` (sql/041/084): se van los cuatro statements que apagaban o
-- reasignaban share directo. La cascada contextual no cambia.
CREATE OR REPLACE FUNCTION obras_transferir(
  p_obra_id              uuid,
  p_a_usuario_id         uuid,
  p_contactos_exclusivos uuid[] DEFAULT '{}'
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

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_contactos_exclusivos)
      AND id IN (SELECT persona_id FROM obras_obra_persona WHERE obra_id = p_obra_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  IF p_a_usuario_id <> auth.uid() THEN
    INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
    SELECT DISTINCT op.persona_id, p_a_usuario_id, p_obra_id, auth.uid()
    FROM obras_obra_persona op
    JOIN obras_personas p ON p.id = op.persona_id
    WHERE op.obra_id = p_obra_id AND op.activo
      AND p.creado_por = v_actual
      AND NOT (op.persona_id = ANY(p_contactos_exclusivos))
    ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
  END IF;

  WITH movidas AS (
    UPDATE obras_empresas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_contactos_exclusivos)
      AND id IN (SELECT empresa_id FROM obras_obra_empresa WHERE obra_id = p_obra_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_empresas FROM movidas;

  UPDATE obras_obra_compartida SET activo = false
  WHERE obra_id = p_obra_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_empresa_grant_contextual SET activo = false
  WHERE empresa_id = ANY(v_empresas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND activo;

  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas));

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas)
         OR persona_id = ANY(v_personas));

  IF p_a_usuario_id <> auth.uid() THEN
    INSERT INTO obras_empresa_grant_contextual (empresa_id, usuario_id, obra_id, otorgada_por)
    SELECT DISTINCT oe.empresa_id, p_a_usuario_id, p_obra_id, auth.uid()
    FROM obras_obra_empresa oe
    JOIN obras_empresas e ON e.id = oe.empresa_id
    WHERE oe.obra_id = p_obra_id AND oe.activo
      AND e.creado_por = v_actual
      AND NOT (oe.empresa_id = ANY(p_contactos_exclusivos))
    ON CONFLICT (empresa_id, usuario_id, obra_id)
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
  END IF;
END;
$$;

-- `obras_transferir_persona` / `_empresa`: sale el apagado del share directo.
CREATE OR REPLACE FUNCTION obras_transferir_persona(p_persona_id uuid, p_a_usuario_id uuid)
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

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
    WHERE persona_id = p_persona_id AND activo;

  INSERT INTO obras_transferencias (tipo, persona_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('persona', p_persona_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION obras_transferir_empresa(
  p_empresa_id         uuid,
  p_a_usuario_id       uuid,
  p_personas_exclusivas uuid[] DEFAULT '{}'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual uuid;
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
    WHERE empresa_id = p_empresa_id AND activo;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND activo;

  UPDATE obras_personas SET creado_por = p_a_usuario_id
  WHERE creado_por = v_actual AND id = ANY(p_personas_exclusivas)
    AND id IN (SELECT persona_id FROM obras_persona_empresa WHERE empresa_id = p_empresa_id AND activo);

  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('empresa', p_empresa_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- `obras_compartir_registros` (sql/062/064/082/085): la rama persona pierde el
-- fallback "empresa compartida directo". Sin share directo de empresa, el único
-- ancla posible es una obra compartida con ese usuario; si no hay, OB029.
-- Sigue a medio camino por lo mismo de siempre: el chip de la tarea no lleva
-- `?ctx=` (BACKLOG.md).
CREATE OR REPLACE FUNCTION obras_compartir_registros(p_usuario uuid, p_registros jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  x             jsonb;
  v_ente        text;
  v_id          uuid;
  v_origen_obra uuid;
BEGIN
  IF p_usuario = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte un registro a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  FOR x IN
    SELECT e
    FROM jsonb_array_elements(COALESCE(p_registros, '[]'::jsonb)) AS e
    ORDER BY CASE e->>'ente' WHEN 'obra' THEN 1 WHEN 'empresa' THEN 2 ELSE 3 END
  LOOP
    v_ente := x->>'ente';
    v_id   := (x->>'registro_id')::uuid;

    IF v_ente = 'obra' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras o WHERE o.id = v_id AND o.responsable_id = auth.uid() AND o.activo
      ) THEN
        RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
      END IF;

      INSERT INTO obras_obra_compartida (obra_id, usuario_id, otorgada_por, activo)
      VALUES (v_id, p_usuario, auth.uid(), true)
      ON CONFLICT (obra_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now()
        WHERE NOT obras_obra_compartida.activo;

    ELSIF v_ente = 'empresa' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras_empresas e
        WHERE e.id = v_id AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
      ) THEN
        RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
      END IF;

      SELECT oe.obra_id INTO v_origen_obra
      FROM obras_obra_empresa oe
      JOIN obras o ON o.id = oe.obra_id AND o.responsable_id = auth.uid() AND o.activo
      JOIN obras_obra_compartida c ON c.obra_id = oe.obra_id AND c.usuario_id = p_usuario AND c.activo
      WHERE oe.empresa_id = v_id AND oe.activo
      LIMIT 1;

      IF v_origen_obra IS NULL THEN
        RAISE EXCEPTION 'Esa empresa no cuelga de ninguna obra compartida con ese usuario: compartí la obra y tildala en el checklist'
          USING ERRCODE = 'OB029';
      END IF;

      INSERT INTO obras_empresa_grant_contextual
        (empresa_id, usuario_id, obra_id, otorgada_por, activo)
      VALUES (v_id, p_usuario, v_origen_obra, auth.uid(), true)
      ON CONFLICT (empresa_id, usuario_id, obra_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now()
        WHERE NOT obras_empresa_grant_contextual.activo;

    ELSIF v_ente = 'persona' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras_personas p
        WHERE p.id = v_id AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
      ) THEN
        RAISE EXCEPTION 'Solo el dueño de la persona puede compartirla' USING ERRCODE = 'OB020';
      END IF;

      SELECT op.obra_id INTO v_origen_obra
      FROM obras_obra_persona op
      JOIN obras o ON o.id = op.obra_id AND o.responsable_id = auth.uid() AND o.activo
      JOIN obras_obra_compartida c ON c.obra_id = op.obra_id AND c.usuario_id = p_usuario AND c.activo
      WHERE op.persona_id = v_id AND op.activo
      LIMIT 1;

      IF v_origen_obra IS NULL THEN
        RAISE EXCEPTION 'Esa persona no cuelga de ninguna obra compartida con ese usuario: compartí la obra y tildala en el checklist'
          USING ERRCODE = 'OB029';
      END IF;

      INSERT INTO obras_persona_grant_contextual
        (persona_id, usuario_id, obra_id, otorgada_por, activo)
      VALUES (v_id, p_usuario, v_origen_obra, auth.uid(), true)
      ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
      DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now()
        WHERE NOT obras_persona_grant_contextual.activo;
    END IF;
  END LOOP;
END;
$$;

-- ============================================================
-- 4b. Revocar una fila suelta del checklist
--
-- La vista Compartido tiene una X por fila. Para las hijas la revocaban
-- `obras_revocar_persona` / `_empresa`, que se van. Reemplazo mínimo: apagar el
-- grant contextual de esa entidad, para ese usuario, anclado en esa obra. Es lo
-- mismo que destildarla en el checklist, desde el otro lado.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_revocar_contextual(
  p_tipo       text,
  p_entidad_id uuid,
  p_usuario_id uuid,
  p_obra_id    uuid
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras o WHERE o.id = p_obra_id AND o.responsable_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede revocar el acceso' USING ERRCODE = 'OB026';
  END IF;

  IF p_tipo = 'empresa' THEN
    UPDATE obras_empresa_grant_contextual
      SET activo = false, updated_at = now()
      WHERE empresa_id = p_entidad_id AND usuario_id = p_usuario_id
        AND obra_id = p_obra_id AND activo;
  ELSIF p_tipo = 'persona' THEN
    UPDATE obras_persona_grant_contextual
      SET activo = false, updated_at = now()
      WHERE persona_id = p_entidad_id AND usuario_id = p_usuario_id
        AND obra_id = p_obra_id AND activo;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_revocar_contextual(text, uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_revocar_contextual(text, uuid, uuid, uuid) TO authenticated;

-- ============================================================
-- 5. Lo que se va
--
-- `obras_compartir_persona` / `_empresa` y sus revocar: la segunda puerta.
-- `obras_relaciones_compartibles_empresa`: era el checklist de esa puerta.
-- `obras_*_grant_directo` (sql/052) y `obras_*_compartida_conmigo` (sql/051):
-- sin la tabla, siempre false. Ya no los llama nadie (pasos 2 y 4).
-- ============================================================
DROP FUNCTION IF EXISTS obras_compartir_persona(uuid, uuid);
DROP FUNCTION IF EXISTS obras_compartir_empresa(uuid, uuid, uuid[]);
DROP FUNCTION IF EXISTS obras_revocar_persona(uuid, uuid);
DROP FUNCTION IF EXISTS obras_revocar_empresa(uuid, uuid);
DROP FUNCTION IF EXISTS obras_relaciones_compartibles_empresa(uuid, uuid);
DROP FUNCTION IF EXISTS obras_persona_grant_directo(uuid);
DROP FUNCTION IF EXISTS obras_empresa_grant_directo(uuid);
DROP FUNCTION IF EXISTS obras_persona_compartida_conmigo(uuid);
DROP FUNCTION IF EXISTS obras_empresa_compartida_conmigo(uuid);
DROP FUNCTION IF EXISTS obras_contar_vinculos_persona_receptor(uuid, uuid);
DROP FUNCTION IF EXISTS obras_contar_vinculos_empresa_receptor(uuid, uuid);

-- Las dos tablas quedan sin escritor y sin lector. Se dropean: el paso 1 ya
-- apagó lo que hubiera, y los eventos `compartido`/`revocado` que emitieron
-- siguen en `eventos`.
DROP TABLE IF EXISTS obras_persona_compartida;
DROP TABLE IF EXISTS obras_empresa_compartida;

COMMIT;
