-- ============================================================
-- 088 — Migrar toda la agenda de un usuario a otro
--
-- Pedido del usuario junto con sql/087: "una nueva función de transferir toda
-- la agenda de un usuario a otro (...) sería una función y vista aparte donde
-- el usuario que tiene permiso selecciona un usuario y decide migrar todos sus
-- datos". El caso es que alguien se va de la empresa.
--
-- **Sin checklist.** `obras_transferir` pregunta tres cosas por contacto porque
-- el saliente sigue trabajando acá y algo suyo queda. Acá no queda nadie: una
-- agenda de 400 contactos no se tilda fila por fila y no hay decisión razonable
-- que tomar 400 veces. Cascada total y una sola confirmación.
--
-- Qué se mueve:
--   · `obras.responsable_id`         — sus obras
--   · `obras_personas.creado_por`    — su agenda de contactos
--   · `obras_empresas.creado_por`    — sus empresas
--   · `obras_obra_persona.creado_por` / `obras_obra_empresa.creado_por` — los
--     vínculos que creó, **incluidos los que creó en obras de otros**
--   · los grants que otorgó (`otorgada_por`) y los que recibió (`usuario_id`)
--
-- El detalle que no es obvio son los vínculos en obras ajenas (sql/051). Si no
-- se movieran, quedarían con el `creado_por` de alguien que ya no está, y
-- `obras_vinculo_guard_edicion` (OB028) dice que solo su creador los edita.
-- `obras_transferir` los deja a propósito ("queda a decisión del nuevo dueño"),
-- pero ahí el saliente sigue existiendo; acá no. Verificado contra el cuerpo
-- vivo del guard: dispara solo si `obras_obra_compartida_con(obra, creado_por)`,
-- así que las dos ramas mejoran al mover el creador —
--   · si el entrante tiene esa obra compartida, la edita él;
--   · si no la tiene, el guard deja de disparar y el dueño de la obra recupera
--     la edición de su propia fila.
-- La alternativa (no moverlos) las congela para todos, para siempre.
--
-- Decisión del usuario sobre lo RECIBIDO: los grants donde el saliente es
-- `usuario_id` —lo que terceros le compartieron— **pasan al entrante**. El
-- reemplazo ocupa el lugar del que se fue, también para mirar. El que otorgó
-- sigue siendo `otorgada_por`, lo ve en su vista Compartido y puede revocarlo:
-- ese es el recurso del tercero que no eligió al entrante.
--
-- Y el log: una fila en `obras_transferencias` por entidad movida. Los avisos
-- salen solo por obra — el trigger `trg_notificar_transferencia_obra` filtra
-- `WHEN (NEW.tipo = 'obra')` desde sql/041. 30 obras = 30 avisos, ruidoso pero
-- cada uno navega a algo real. No se agrupan.
--
-- §4 arregla `obras_auditoria_transferencias`, que hacía INNER JOIN con `obras`
-- y por eso nunca mostró una transferencia de persona ni de empresa. Sin eso el
-- log de esta migración se escribe y no lo lee nadie, y las transferencias
-- sueltas de sql/087 ya estaban invisibles.
--
-- Ver decisiones/obras/visibilidad.md.
-- ============================================================
BEGIN;

-- ============================================================
-- 1. El submódulo
--
-- Vista y no función: es una pantalla propia, y las pantallas del módulo son
-- tabs. No se reutilizan `obras_transferir` / `obras_personas_todas` /
-- `obras_empresas_todas`: quien vacía la agenda de alguien que se fue no es
-- necesariamente quien reasigna una obra suelta, y al revés.
--
-- La vista es la única puerta: no lleva submódulo-función abajo porque la
-- pantalla hace una sola cosa, y una función que cubre exactamente su vista es
-- ceremonia (GUIDE_PERMISSIONS: una vista puede no tener funciones).
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden) VALUES
  ('obras_migrar', 'obras', 'vista', 'Migrar agenda', 7)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

-- ============================================================
-- 2. El resumen — qué se va a mover
--
-- La confirmación escribiendo el nombre no significa nada si la pantalla no
-- dice qué hay del otro lado. Conteos, no listados: la lista de 400 contactos
-- no cambia ninguna decisión, porque no hay nada que tildar.
--
-- `vinculos_ajenos` se muestra aparte a propósito: es lo que nadie espera y lo
-- único que toca fichas de terceros.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_migrar_resumen(p_de_usuario uuid)
RETURNS TABLE (
  obras           bigint,
  empresas        bigint,
  personas        bigint,
  vinculos_ajenos bigint,
  otorgados       bigint,
  recibidos       bigint
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_migrar') THEN
    RAISE EXCEPTION 'Sin permiso para migrar agendas' USING ERRCODE = 'OB033';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM obras o
      WHERE o.responsable_id = p_de_usuario AND o.activo),

    (SELECT count(*) FROM obras_empresas e
      WHERE e.creado_por = p_de_usuario AND e.activo),

    (SELECT count(*) FROM obras_personas p
      WHERE p.creado_por = p_de_usuario AND p.activo),

    (SELECT count(*) FROM obras_obra_persona op
       JOIN obras o ON o.id = op.obra_id AND o.activo
      WHERE op.creado_por = p_de_usuario AND op.activo
        AND o.responsable_id <> p_de_usuario)
    + (SELECT count(*) FROM obras_obra_empresa oe
         JOIN obras o ON o.id = oe.obra_id AND o.activo
        WHERE oe.creado_por = p_de_usuario AND oe.activo
          AND o.responsable_id <> p_de_usuario),

    (SELECT count(*) FROM obras_obra_compartida g
      WHERE g.otorgada_por = p_de_usuario AND g.activo)
    + (SELECT count(*) FROM obras_persona_grant_contextual g
        WHERE g.otorgada_por = p_de_usuario AND g.activo)
    + (SELECT count(*) FROM obras_empresa_grant_contextual g
        WHERE g.otorgada_por = p_de_usuario AND g.activo),

    (SELECT count(*) FROM obras_obra_compartida g
      WHERE g.usuario_id = p_de_usuario AND g.activo)
    + (SELECT count(*) FROM obras_persona_grant_contextual g
        WHERE g.usuario_id = p_de_usuario AND g.activo)
    + (SELECT count(*) FROM obras_empresa_grant_contextual g
        WHERE g.usuario_id = p_de_usuario AND g.activo);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_migrar_resumen(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_migrar_resumen(uuid) TO authenticated;

-- ============================================================
-- 3. La migración
--
-- Orden de los pasos, que importa:
--   3.1 entidades  — después de esto el saliente no posee nada
--   3.2 vínculos   — incluidos los de obras ajenas
--   3.3 saneo      — nadie recibe un grant sobre lo que ahora es suyo
--   3.4 otorgados  — los grants que dio el saliente cuelgan del entrante
--   3.5 recibidos  — los grants que recibió pasan al entrante
--
-- 3.3 va antes de 3.4/3.5 porque el CHECK `usuario_id <> otorgada_por` es
-- inmediato: no se puede dejar la fila en estado inválido ni por un statement.
--
-- Se mueve todo, activo o no: un contacto desactivado que quedara con el
-- `creado_por` del saliente vuelve a la vida sin dueño el día que alguien lo
-- reactive. El log, en cambio, solo registra lo activo — es la auditoría de lo
-- que opera, no un inventario del cementerio.
-- ============================================================
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

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
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

REVOKE EXECUTE ON FUNCTION public.obras_migrar_agenda(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_migrar_agenda(uuid, uuid) TO authenticated;

-- ============================================================
-- 4. La auditoría veía una transferencia de cada tres
--
-- `obras_auditoria_transferencias` hacía `JOIN obras o ON o.id = t.obra_id`.
-- Las filas de persona y empresa tienen `obra_id` NULL (CHECK
-- `transferencia_tipo_ancla`), así que el INNER las descartaba: desde sql/041
-- se escriben y nunca se leyeron. Con la migración masiva pasa de detalle a
-- agujero — el log por entidad existe para que alguien lo lea.
--
-- LEFT JOIN no alcanza porque el nombre sale de tres tablas distintas:
-- `obras_etiqueta(tipo, id)` (sql/033) ya resuelve las tres y es la misma
-- pregunta, así que no se escribe un CASE nuevo.
--
-- DROP + CREATE y no OR REPLACE: cambia el tipo de retorno.
-- ============================================================
DROP FUNCTION IF EXISTS obras_auditoria_transferencias(integer);

CREATE FUNCTION obras_auditoria_transferencias(p_dias integer DEFAULT 90)
RETURNS TABLE (
  transferencia_id uuid,
  created_at       timestamptz,
  tipo             text,
  entidad_id       uuid,
  entidad          text,
  de_usuario       text,
  a_usuario        text,
  ejecutada_por    text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_auditoria') THEN
    RAISE EXCEPTION 'Sin permiso para ver la auditoría' USING ERRCODE = 'OB010';
  END IF;

  RETURN QUERY
  SELECT t.id, t.created_at, t.tipo,
         coalesce(t.obra_id, t.persona_id, t.empresa_id),
         obras_etiqueta(t.tipo, coalesce(t.obra_id, t.persona_id, t.empresa_id)),
         ud.nombre, ua.nombre, ue.nombre
  FROM obras_transferencias t
  JOIN usuarios ud ON ud.id = t.de_usuario_id
  JOIN usuarios ua ON ua.id = t.a_usuario_id
  JOIN usuarios ue ON ue.id = t.ejecutada_por
  WHERE t.created_at >= now() - make_interval(days => greatest(p_dias, 1))
  ORDER BY t.created_at DESC
  LIMIT 500;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_auditoria_transferencias(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_auditoria_transferencias(integer) TO authenticated;

COMMIT;
