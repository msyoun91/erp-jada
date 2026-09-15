-- ============================================================
-- 062 — Quién puede abrir un registro, preguntado por usuario
--
-- Fase C de PLAN_TAREAS_VINCULOS.md (decidido con el usuario el 2026-09-14,
-- BACKLOG.md → "Compartir al asignar"). La base necesita contestar "¿el
-- usuario U puede abrir el registro R?" y "¿puedo compartírselo?" sin copiar
-- la visibilidad de Obras (decisiones/obras/visibilidad.md, MODEL A), para
-- que Tareas pueda decidir quién queda asignado (Fase D) y la UI pueda
-- ofrecer compartir (Fase E).
--
-- Todas las funciones son SECURITY DEFINER STABLE salvo que se diga otra
-- cosa. "Sin GRANT" = REVOKE FROM PUBLIC y nada más: solo las llaman otras
-- DEFINER, nunca el cliente directo.
-- ============================================================

-- ============================================================
-- 1. tiene_permiso por usuario explícito
--
-- El cuerpo de sql/020, parametrizado. tiene_permiso(p_codigo) pasa a
-- envoltorio de una línea — misma firma, misma seguridad, mismos grants
-- (CREATE OR REPLACE los conserva).
-- ============================================================
CREATE OR REPLACE FUNCTION usuario_tiene_permiso(p_usuario uuid, p_codigo text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM usuario_submodulos us
    JOIN submodulos s ON s.id = us.submodulo_id
    JOIN usuarios u ON u.id = us.usuario_id
    WHERE us.usuario_id = p_usuario
      AND u.activo
      AND us.activo
      AND s.activo
      AND s.codigo = p_codigo
  );
$$;

REVOKE EXECUTE ON FUNCTION usuario_tiene_permiso(uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION tiene_permiso(p_codigo text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT usuario_tiene_permiso(auth.uid(), p_codigo);
$$;

-- ============================================================
-- 2. Visibilidad de obra/empresa/persona por usuario explícito
--
-- Los cuerpos vigentes de obras_puede_ver_obra/_persona/_empresa
-- (sql/039, con la rama de obras_obra_compartida de sql/047), con
-- auth.uid() -> p_usuario y tiene_permiso(x) -> usuario_tiene_permiso(p_usuario, x).
-- Las tres actuales quedan como envoltorios de una línea con auth.uid():
-- no se tocan sus políticas de RLS, que siguen llamándolas igual.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_ver_obra_de(p_obra_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id
      AND (
        (o.responsable_id = p_usuario AND usuario_tiene_permiso(p_usuario, 'obras_ver'))
        OR usuario_tiene_permiso(p_usuario, 'obras_transferir')
        OR (
          usuario_tiene_permiso(p_usuario, 'obras_ver')
          AND EXISTS (
            SELECT 1 FROM obras_obra_compartida c
            WHERE c.obra_id = o.id AND c.usuario_id = p_usuario AND c.activo
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION obras_puede_ver_empresa_de(p_empresa_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT (usuario_tiene_permiso(p_usuario, 'obras_ver') OR usuario_tiene_permiso(p_usuario, 'obras_empresas'))
    AND EXISTS (
      SELECT 1 FROM obras_empresas e
      WHERE e.id = p_empresa_id AND e.activo
        AND (
          e.creado_por = p_usuario
          OR (
            NOT e.pendiente
            AND (
              usuario_tiene_permiso(p_usuario, 'obras_empresas_todas')
              OR EXISTS (
                SELECT 1 FROM obras_empresa_compartida c
                WHERE c.empresa_id = p_empresa_id AND c.usuario_id = p_usuario AND c.activo
              )
            )
          )
        )
    );
$$;

CREATE OR REPLACE FUNCTION obras_puede_ver_persona_de(p_persona_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT (usuario_tiene_permiso(p_usuario, 'obras_ver') OR usuario_tiene_permiso(p_usuario, 'obras_personas'))
    AND EXISTS (
      SELECT 1 FROM obras_personas p
      WHERE p.id = p_persona_id
        AND (
          p.creado_por = p_usuario
          OR (
            NOT p.pendiente
            AND (
              usuario_tiene_permiso(p_usuario, 'obras_personas_todas')
              OR EXISTS (
                SELECT 1 FROM obras_persona_compartida c
                WHERE c.persona_id = p_persona_id AND c.usuario_id = p_usuario AND c.activo
              )
            )
          )
        )
    );
$$;

REVOKE EXECUTE ON FUNCTION obras_puede_ver_obra_de(uuid, uuid)     FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_puede_ver_empresa_de(uuid, uuid)  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_puede_ver_persona_de(uuid, uuid)  FROM PUBLIC;

-- Envoltorios: no cambian firma ni grants (CREATE OR REPLACE los conserva).
CREATE OR REPLACE FUNCTION obras_puede_ver_obra(p_obra_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT obras_puede_ver_obra_de(p_obra_id, auth.uid()); $$;

CREATE OR REPLACE FUNCTION obras_puede_ver_empresa(p_empresa_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT obras_puede_ver_empresa_de(p_empresa_id, auth.uid()); $$;

CREATE OR REPLACE FUNCTION obras_puede_ver_persona(p_persona_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT obras_puede_ver_persona_de(p_persona_id, auth.uid()); $$;

-- ============================================================
-- 3. obras_puede_abrir — un CASE por tipo, sin grant contextual
--
-- El chip de un vínculo abre la ficha sin contexto (obra|empresa), así que
-- el grant contextual de persona (obras_persona_grant_ctx_vigente) no cuenta:
-- ese solo vale adentro de la ficha que lo trajo.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra'    THEN obras_puede_ver_obra_de(p_id, p_usuario)
    WHEN 'empresa' THEN obras_puede_ver_empresa_de(p_id, p_usuario)
    WHEN 'persona' THEN obras_puede_ver_persona_de(p_id, p_usuario)
  END;
$$;

REVOKE EXECUTE ON FUNCTION obras_puede_abrir(text, uuid, uuid) FROM PUBLIC;

-- ============================================================
-- 4. puede_abrir_registro — la misma puerta que la ruta de la ficha
--
-- Submódulo del ente más la fila. Un módulo que registre entes suma su rama,
-- como en etiqueta_registro (sql/059).
-- ============================================================
CREATE OR REPLACE FUNCTION puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT e.activo
       AND usuario_tiene_permiso(p_usuario, e.submodulo)
       AND CASE e.modulo
             WHEN 'obras' THEN obras_puede_abrir(e.codigo, p_id, p_usuario)
           END
     FROM entes e
     WHERE e.codigo = p_ente),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION puede_abrir_registro(text, uuid, uuid) FROM PUBLIC;

-- ============================================================
-- 5. queda_afuera — único predicado de la regla, quien actúa exento
-- ============================================================
CREATE OR REPLACE FUNCTION queda_afuera(p_usuario uuid, p_ente text, p_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT p_usuario IS DISTINCT FROM auth.uid()
    AND NOT puede_abrir_registro(p_ente, p_id, p_usuario);
$$;

REVOKE EXECUTE ON FUNCTION queda_afuera(uuid, text, uuid) FROM PUBLIC;

-- ============================================================
-- 6. obras_puede_compartir — que sea de quien llama
--
-- Mismos cortes que OB026 (obra) / OB020 (empresa, persona) en
-- obras_compartir_obra/_empresa/_persona.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_compartir(p_tipo text, p_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN EXISTS (
      SELECT 1 FROM obras o WHERE o.id = p_id AND o.responsable_id = auth.uid() AND o.activo
    )
    WHEN 'empresa' THEN EXISTS (
      SELECT 1 FROM obras_empresas e
      WHERE e.id = p_id AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
    )
    WHEN 'persona' THEN EXISTS (
      SELECT 1 FROM obras_personas p
      WHERE p.id = p_id AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    )
  END;
$$;

REVOKE EXECUTE ON FUNCTION obras_puede_compartir(text, uuid) FROM PUBLIC;

-- ============================================================
-- 7. puede_compartir_registro
--
-- Sin el submódulo, compartir no le abre nada al destinatario: se lo excluye
-- igual que si no pudiera abrirlo.
-- ============================================================
CREATE OR REPLACE FUNCTION puede_compartir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT p_usuario <> auth.uid()
       AND EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario AND u.activo)
       AND e.activo
       AND usuario_tiene_permiso(p_usuario, e.submodulo)
       AND CASE e.modulo
             WHEN 'obras' THEN obras_puede_compartir(e.codigo, p_id)
           END
     FROM entes e
     WHERE e.codigo = p_ente),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION puede_compartir_registro(text, uuid, uuid) FROM PUBLIC;

-- ============================================================
-- 8. asignados_con_acceso — GRANT authenticated (la llaman crear_tarea /
-- sincronizar_asignados, que son INVOKER — Fase D)
-- ============================================================
CREATE OR REPLACE FUNCTION asignados_con_acceso(p_asignados uuid[], p_vinculos jsonb)
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(a.usuario_id ORDER BY a.ord), ARRAY[]::uuid[])
  FROM unnest(p_asignados) WITH ORDINALITY AS a(usuario_id, ord)
  WHERE NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(COALESCE(p_vinculos, '[]'::jsonb)) v
    WHERE queda_afuera(a.usuario_id, v->>'ente', (v->>'registro_id')::uuid)
  );
$$;

REVOKE EXECUTE ON FUNCTION asignados_con_acceso(uuid[], jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION asignados_con_acceso(uuid[], jsonb) TO authenticated;

-- ============================================================
-- 9. sin_acceso — GRANT authenticated
--
-- El CASE de la etiqueta es obligatorio: adentro de una DEFINER,
-- etiqueta_registro corre sin la RLS de quien llama y devolvería el nombre
-- de lo que no ve. Exposición aceptada, registrada en decisiones/: deja
-- preguntar si otro usuario puede abrir un id que ya conocés, sin devolver
-- el nombre de lo que no ves — el id suelto (uuid) no vale nada.
-- ============================================================
CREATE OR REPLACE FUNCTION sin_acceso(p_pares jsonb)
RETURNS TABLE (
  usuario_id  uuid,
  usuario     text,
  ente        text,
  registro_id uuid,
  etiqueta    text,
  compartible boolean
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT DISTINCT
    (x->>'usuario_id')::uuid,
    u.nombre,
    x->>'ente',
    (x->>'registro_id')::uuid,
    CASE WHEN puede_abrir_registro(x->>'ente', (x->>'registro_id')::uuid, auth.uid())
         THEN etiqueta_registro(x->>'ente', (x->>'registro_id')::uuid)
    END,
    puede_compartir_registro(x->>'ente', (x->>'registro_id')::uuid, (x->>'usuario_id')::uuid)
  FROM jsonb_array_elements(COALESCE(p_pares, '[]'::jsonb)) x
  JOIN usuarios u ON u.id = (x->>'usuario_id')::uuid
  WHERE queda_afuera((x->>'usuario_id')::uuid, x->>'ente', (x->>'registro_id')::uuid)
  ORDER BY 2, 5;
$$;

REVOKE EXECUTE ON FUNCTION sin_acceso(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION sin_acceso(jsonb) TO authenticated;

-- ============================================================
-- 10. obras_compartir_registros — aditiva, GRANT authenticated
--
-- p_registros: [{ente, registro_id}], todos de obras. Un grant activo no se
-- toca (WHERE NOT ...activo en el ON CONFLICT): no se le cambia el origen ni
-- se apaga ninguna cascada — a diferencia de obras_compartir_obra/_empresa
-- (sql/049, "estado deseado"), esta es solo aditiva.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartir_registros(p_usuario uuid, p_registros jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  x               jsonb;
  v_ente          text;
  v_id            uuid;
  v_origen_obra   uuid;
  v_origen_empresa uuid;
BEGIN
  IF p_usuario = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte un registro a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_registros, '[]'::jsonb))
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

      INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por, activo, origen_obra_id)
      VALUES (v_id, p_usuario, auth.uid(), true, v_origen_obra)
      ON CONFLICT (empresa_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
            origen_obra_id = EXCLUDED.origen_obra_id
        WHERE NOT obras_empresa_compartida.activo;

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

      v_origen_empresa := NULL;
      IF v_origen_obra IS NULL THEN
        SELECT pe.empresa_id INTO v_origen_empresa
        FROM obras_persona_empresa pe
        JOIN obras_empresas e ON e.id = pe.empresa_id AND e.creado_por = auth.uid() AND e.activo
        JOIN obras_empresa_compartida c ON c.empresa_id = pe.empresa_id AND c.usuario_id = p_usuario AND c.activo
        WHERE pe.persona_id = v_id AND pe.activo
        LIMIT 1;
      END IF;

      INSERT INTO obras_persona_compartida
        (persona_id, usuario_id, otorgada_por, activo, origen_obra_id, origen_empresa_id)
      VALUES (v_id, p_usuario, auth.uid(), true, v_origen_obra, v_origen_empresa)
      ON CONFLICT (persona_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
            origen_obra_id = EXCLUDED.origen_obra_id,
            origen_empresa_id = EXCLUDED.origen_empresa_id
        WHERE NOT obras_persona_compartida.activo;
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION obras_compartir_registros(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION obras_compartir_registros(uuid, jsonb) TO authenticated;

-- ============================================================
-- 11. compartir_registros — INVOKER, GRANT authenticated
--
-- Agrupa por usuario y por entes.modulo. Un módulo nuevo suma su rama acá.
-- ============================================================
CREATE OR REPLACE FUNCTION compartir_registros(p_selecciones jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT (x->>'usuario_id')::uuid AS usuario_id,
           e.modulo AS modulo,
           jsonb_agg(jsonb_build_object('ente', x->>'ente', 'registro_id', x->>'registro_id')) AS registros
    FROM jsonb_array_elements(COALESCE(p_selecciones, '[]'::jsonb)) x
    JOIN entes e ON e.codigo = x->>'ente'
    GROUP BY (x->>'usuario_id')::uuid, e.modulo
  LOOP
    IF r.modulo = 'obras' THEN
      PERFORM obras_compartir_registros(r.usuario_id, r.registros);
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION compartir_registros(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION compartir_registros(jsonb) TO authenticated;
