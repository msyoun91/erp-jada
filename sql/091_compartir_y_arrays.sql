-- sql/091 — el receptor sin Obras, el array NULL y la cuarta copia del gate
--
-- Resto de la auditoría de compartir/transferir (2026-09-18), las tres entradas
-- del `BACKLOG.md` que se arreglan en SQL y sin decidir nada nuevo. Ninguna es
-- un acceso indebido: son grants que no abren nada, degradaciones silenciosas y
-- una regla escrita de más.
--
--   1. `obras_compartir_obra` no verificaba que el receptor tenga `obras_ver`.
--      Transferir sí (OB006). Compartir con alguien sin acceso al módulo crea
--      un grant que no abre nada: la obra no le aparece (`obras_select` exige
--      `obras_ver`) y, desde sql/090, los contextuales que cuelgan tampoco.
--   2. `NULL` degradaba en silencio en los arrays. `id = ANY(NULL)` es NULL, no
--      false, y el `DEFAULT '{}'` de la firma no aplica cuando el cliente manda
--      `null` explícito. Compartir con `p_personas: null` no otorgaba **ni
--      destildaba** — el `NOT (... = ANY(...))` de la limpieza también da NULL,
--      así que el reparto quedaba congelado. `obras_transferir` con
--      `p_migran: null` transfería la obra y dejaba al receptor sin ningún
--      contacto, ni migrado ni contextual.
--   3. `obras_migrar_agenda` conservaba la copia del gate OB006 como EXISTS
--      sobre `usuario_submodulos`. sql/090 pasó las otras tres a
--      `usuario_tiene_permiso`; esta era la cuarta y última.
--
-- Sobre el código de error de (1): se reusa OB006 y no uno nuevo. Es la misma
-- regla —"ese usuario no tiene acceso a Obras"— y un código por regla es lo que
-- OB022 dejó de cumplir. El texto sí cambia: acá el usuario no es "el destino"
-- de una transferencia sino el receptor de un share, y `mensajeError()` muestra
-- el texto de la base, así que el código identifica y el mensaje explica.
--
-- Alcance de (2): son las tres funciones con `uuid[]` alcanzables por
-- `authenticated`. `obras_transferir_resolver_vinculos` también recibe arrays,
-- pero no tiene GRANT —solo la llaman las otras, ya saneadas—, así que
-- blindarla sería código muerto.
--
-- Test: sql/tests/obras_091.sql

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · Compartir una obra: el receptor tiene que poder abrirla
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_compartir_obra(
  p_obra_id    uuid,
  p_usuario_id uuid,
  p_empresas   uuid[] DEFAULT '{}',
  p_personas   uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- `id = ANY(NULL)` es NULL, no false, y el DEFAULT '{}' de la firma no aplica
  -- cuando el cliente manda `null` explícito. Sin esto, destildar no destilda:
  -- el `NOT (... = ANY(...))` de la limpieza también da NULL y el reparto queda
  -- congelado. Mismo blindaje en las dos funciones de transferir.
  p_empresas := COALESCE(p_empresas, '{}');
  p_personas := COALESCE(p_personas, '{}');

  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una obra a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid() AND o.activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;
  IF NOT usuario_tiene_permiso(p_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El usuario no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  INSERT INTO obras_obra_compartida (obra_id, usuario_id, otorgada_por, activo)
  VALUES (p_obra_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (obra_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  -- Empresas tildadas: vinculadas a esta obra y mías. Se abren dentro de esta
  -- obra, no entran a la agenda del receptor.
  INSERT INTO obras_empresa_grant_contextual
    (empresa_id, usuario_id, obra_id, otorgada_por, activo)
  SELECT DISTINCT oe.empresa_id, p_usuario_id, p_obra_id, auth.uid(), true
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
    AND oe.empresa_id = ANY(p_empresas)
  ON CONFLICT (empresa_id, usuario_id, obra_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  -- Personas tildadas: igual, ancladas a esta obra (sql/082).
  INSERT INTO obras_persona_grant_contextual
    (persona_id, usuario_id, obra_id, otorgada_por, activo)
  SELECT DISTINCT op.persona_id, p_usuario_id, p_obra_id, auth.uid(), true
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND op.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  -- Estado deseado (sql/049): lo destildado se apaga, por ancla.
  UPDATE obras_empresa_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (empresa_id = ANY(p_empresas));

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (persona_id = ANY(p_personas));
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · Transferir: el array NULL no puede vaciar el reparto
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

  -- Lo compartido con terceros sigue vivo pero cuelga del nuevo dueño: quien
  -- recibe es quien ahora puede revocar. Solo lo anclado a lo que cambió de
  -- mano — la obra, y las empresas que migran, que son ancla de sus personas.
  -- Un grant anclado a OTRA obra del saliente no se toca aunque su entidad se
  -- vaya: esa obra sigue siendo suya, y moverle el otorgante lo dejaba fuera
  -- de su propia vista Compartido con el acceso vivo (V1).
  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND activo;

  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id AND obra_id = p_obra_id;

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas));

  -- Y los estados 2 y 3 sobre lo que se fue.
  PERFORM obras_transferir_resolver_vinculos(
    v_personas, v_empresas, p_sacar, v_actual, p_a_usuario_id, p_obra_id
  );
END;
$$;

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

  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s WHERE NOT (s = ANY(p_migran))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_empresas SET creado_por = p_a_usuario_id WHERE id = p_empresa_id;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = p_empresa_id AND usuario_id = p_a_usuario_id AND activo;

  -- La empresa es ancla de las personas que cuelgan de ella: esos grants sí
  -- cambian de otorgante. Los grants DE la empresa, en cambio, están anclados
  -- a obras que no cambiaron de dueño, así que no se tocan.
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
-- 3 · La cuarta copia del gate OB006
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_migrar_agenda(p_de_usuario uuid, p_a_usuario uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_migrar') THEN
    RAISE EXCEPTION 'Sin permiso para migrar agendas' USING ERRCODE = 'OB033';
  END IF;

  IF p_de_usuario = p_a_usuario THEN
    RAISE EXCEPTION 'La agenda ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  -- El saliente puede estar desactivado: migrar primero y desactivar después es
  -- el orden sano, pero el inverso tiene que seguir funcionando.
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_de_usuario) THEN
    RAISE EXCEPTION 'El usuario saliente no existe' USING ERRCODE = 'OB034';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  -- ---- 3.1 Entidades ----
  WITH movidas AS (
    UPDATE obras SET responsable_id = p_a_usuario
    WHERE responsable_id = p_de_usuario
    RETURNING id, activo
  )
  INSERT INTO obras_transferencias (tipo, obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  SELECT 'obra', id, p_de_usuario, p_a_usuario, auth.uid() FROM movidas WHERE activo;

  WITH movidas AS (
    UPDATE obras_empresas SET creado_por = p_a_usuario
    WHERE creado_por = p_de_usuario
    RETURNING id, activo
  )
  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  SELECT 'empresa', id, p_de_usuario, p_a_usuario, auth.uid() FROM movidas WHERE activo;

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario
    WHERE creado_por = p_de_usuario
    RETURNING id, activo
  )
  INSERT INTO obras_transferencias (tipo, persona_id, de_usuario_id, a_usuario_id, ejecutada_por)
  SELECT 'persona', id, p_de_usuario, p_a_usuario, auth.uid() FROM movidas WHERE activo;

  -- ---- 3.2 Vínculos ----
  -- Sin log: `obras_transferencias.tipo` admite tres valores y un vínculo no es
  -- una entidad. La fila de la obra o del contacto ya cuenta el movimiento.
  -- `guard_edicion` no dispara: mira roles, observaciones y empresa_id, y acá
  -- solo cambia `creado_por`.
  UPDATE obras_obra_persona SET creado_por = p_a_usuario WHERE creado_por = p_de_usuario;
  UPDATE obras_obra_empresa SET creado_por = p_a_usuario WHERE creado_por = p_de_usuario;

  -- ---- 3.3 Saneo: nadie recibe un grant sobre lo que ahora es suyo ----
  -- Mismo saneo que hace `obras_transferir` al cambiar de dueño una obra. Sin
  -- esto, 3.4 chocaría contra el CHECK `usuario_id <> otorgada_por`.
  UPDATE obras_obra_compartida c SET activo = false
  WHERE c.usuario_id = p_a_usuario AND c.activo
    AND EXISTS (SELECT 1 FROM obras o
                WHERE o.id = c.obra_id AND o.responsable_id = p_a_usuario);

  UPDATE obras_persona_grant_contextual g SET activo = false
  WHERE g.usuario_id = p_a_usuario AND g.activo
    AND EXISTS (SELECT 1 FROM obras_personas p
                WHERE p.id = g.persona_id AND p.creado_por = p_a_usuario);

  UPDATE obras_empresa_grant_contextual g SET activo = false
  WHERE g.usuario_id = p_a_usuario AND g.activo
    AND EXISTS (SELECT 1 FROM obras_empresas e
                WHERE e.id = g.empresa_id AND e.creado_por = p_a_usuario);

  -- ---- 3.4 Lo que el saliente otorgó ----
  -- Pasa a colgar del entrante: quien recibe es quien ahora puede revocar. Si
  -- quedara apuntando al saliente, el acceso viviría sin nadie que lo apague.
  -- Lo que le otorgó al entrante muere primero: el entrante ya es el dueño.
  UPDATE obras_obra_compartida SET activo = false
  WHERE otorgada_por = p_de_usuario AND usuario_id = p_a_usuario AND activo;
  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario
  WHERE otorgada_por = p_de_usuario AND usuario_id <> p_a_usuario;

  UPDATE obras_persona_grant_contextual SET activo = false
  WHERE otorgada_por = p_de_usuario AND usuario_id = p_a_usuario AND activo;
  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario
  WHERE otorgada_por = p_de_usuario AND usuario_id <> p_a_usuario;

  UPDATE obras_empresa_grant_contextual SET activo = false
  WHERE otorgada_por = p_de_usuario AND usuario_id = p_a_usuario AND activo;
  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario
  WHERE otorgada_por = p_de_usuario AND usuario_id <> p_a_usuario;

  -- ---- 3.5 Lo que el saliente recibió ----
  -- Tres pasos por tabla, y el orden importa:
  --   a) si el entrante ya tiene fila para la misma llave, se revive la suya —
  --      el UNIQUE no admite dos y mover la del saliente fallaría;
  --   b) se apaga lo del saliente que no puede moverse: la llave ya la ocupa el
  --      entrante, o el otorgante ES el entrante (nadie se comparte consigo
  --      mismo);
  --   c) el resto cambia de mano.
  -- El EXISTS de (b) no filtra por `activo`: el UNIQUE tampoco.
  UPDATE obras_obra_compartida d SET activo = true
  FROM obras_obra_compartida o
  WHERE d.obra_id = o.obra_id AND d.usuario_id = p_a_usuario AND NOT d.activo
    AND o.usuario_id = p_de_usuario AND o.activo;

  UPDATE obras_obra_compartida o SET activo = false
  WHERE o.usuario_id = p_de_usuario AND o.activo
    AND (o.otorgada_por = p_a_usuario
         OR EXISTS (SELECT 1 FROM obras_obra_compartida d
                     WHERE d.obra_id = o.obra_id AND d.usuario_id = p_a_usuario));

  UPDATE obras_obra_compartida SET usuario_id = p_a_usuario
  WHERE usuario_id = p_de_usuario AND activo;

  -- El ancla es obra XOR empresa, así que la llave se compara con IS NOT
  -- DISTINCT FROM: el NULL del ancla que no se usa tiene que matchear.
  UPDATE obras_persona_grant_contextual d SET activo = true
  FROM obras_persona_grant_contextual o
  WHERE d.persona_id = o.persona_id AND d.usuario_id = p_a_usuario AND NOT d.activo
    AND d.obra_id IS NOT DISTINCT FROM o.obra_id
    AND d.empresa_id IS NOT DISTINCT FROM o.empresa_id
    AND o.usuario_id = p_de_usuario AND o.activo;

  UPDATE obras_persona_grant_contextual o SET activo = false
  WHERE o.usuario_id = p_de_usuario AND o.activo
    AND (o.otorgada_por = p_a_usuario
         OR EXISTS (SELECT 1 FROM obras_persona_grant_contextual d
                     WHERE d.persona_id = o.persona_id AND d.usuario_id = p_a_usuario
                       AND d.obra_id IS NOT DISTINCT FROM o.obra_id
                       AND d.empresa_id IS NOT DISTINCT FROM o.empresa_id));

  UPDATE obras_persona_grant_contextual SET usuario_id = p_a_usuario
  WHERE usuario_id = p_de_usuario AND activo;

  UPDATE obras_empresa_grant_contextual d SET activo = true
  FROM obras_empresa_grant_contextual o
  WHERE d.empresa_id = o.empresa_id AND d.obra_id = o.obra_id
    AND d.usuario_id = p_a_usuario AND NOT d.activo
    AND o.usuario_id = p_de_usuario AND o.activo;

  UPDATE obras_empresa_grant_contextual o SET activo = false
  WHERE o.usuario_id = p_de_usuario AND o.activo
    AND (o.otorgada_por = p_a_usuario
         OR EXISTS (SELECT 1 FROM obras_empresa_grant_contextual d
                     WHERE d.empresa_id = o.empresa_id AND d.obra_id = o.obra_id
                       AND d.usuario_id = p_a_usuario));

  UPDATE obras_empresa_grant_contextual SET usuario_id = p_a_usuario
  WHERE usuario_id = p_de_usuario AND activo;
END;
$$;

COMMIT;
