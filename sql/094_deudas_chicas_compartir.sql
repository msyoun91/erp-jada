-- sql/094 — las deudas chicas de la auditoría de compartir/transferir
--
-- Lo que quedó del BACKLOG después de sql/090–093: tres inconsistencias sin
-- acceso indebido detrás. Van juntas porque dos de las tres tocan la misma
-- función, `obras_compartidos_por_mi`.
--
-- 1 · OB022 SIGNIFICABA DOS COSAS. "Sin acceso a esta persona" en
--     `obras_ficha_persona` y "Sin acceso a esta obra" en
--     `obras_vinculos_de_obra` (sql/070). Funcionaba porque `mensajeError()`
--     pasa el texto de la base, así que el costo era que el *código* dejó de
--     identificar: nadie podía atrapar uno sin atrapar el otro.
--
--     No hace falta un código nuevo. `OB009` nació en sql/032 con exactamente
--     este significado —"ficha de persona fuera de alcance", mismo texto— y
--     quedó muerto cuando sql/039 reescribió la función con OB022. Se lo
--     revive: la ficha de persona vuelve a OB009 y OB022 queda significando
--     una sola cosa. De paso la persona queda simétrica con la empresa, que
--     ya tenía código propio (OB030 en `obras_ficha_empresa`).
--
-- 2 · GRANTS ACTIVOS QUE YA NO ABREN NADA. El estado 3 de transferir
--     (`p_sacar`, sql/087) desactiva los vínculos pero deja `activo = true` en
--     los grants contextuales de terceros que colgaban de ellos. El acceso
--     muere bien —`obras_ctx_vigente` exige vínculo vivo desde sql/090—, pero
--     la vista Compartido lista por `g.activo` y sigue mostrando un reparto
--     que no existe.
--
--     La vista no puede llamar a `obras_ctx_vigente`: esa función responde por
--     `auth.uid()`, que acá es el que comparte, no el que recibe. Pero la
--     mitad que hace falta —¿sigue existiendo el vínculo?— no depende de
--     quién pregunta. Se extrae a `obras_ctx_vinculo_vivo` y la usan las dos,
--     que es lo que sql/092 hizo con la vigencia entera: un solo lugar.
--
-- 3 · EL NOMBRE LINKEABA A UNA FICHA QUE NO SE PUEDE ABRIR. Lo dejó sql/093:
--     desde que la autoridad es "dueño del contacto O dueño del ancla", el
--     dueño del ancla ve en Compartido filas de contactos que no son suyos, y
--     el nombre linkeaba a una ficha que le contesta OB022. La vista devuelve
--     ahora si la fila se puede abrir y la UI no linkea cuando no. Es el techo
--     que ya tiene la ficha de la obra —ve el nombre del contacto ajeno y no
--     el teléfono, sql/070 y sql/087—: se informa, no se ensancha el acceso.
--
-- Cero cambios de autorización en este archivo. 1 y 3 son de identificación,
-- 2 es de listado.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · La mitad de la vigencia que no depende de quién pregunta
-- ─────────────────────────────────────────────────────────────────────────────

-- Sin GRANT a authenticated: la llaman `obras_ctx_vigente` y
-- `obras_compartidos_por_mi`, las dos SECURITY DEFINER, así que corre siempre
-- adentro del definer. Exponerla sería superficie sin llamador.
CREATE OR REPLACE FUNCTION obras_ctx_vinculo_vivo(
  p_tipo       text,
  p_entidad_id uuid,
  p_ancla_tipo text,
  p_ancla_id   uuid
)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_tipo = 'empresa' AND p_ancla_tipo = 'obra' THEN EXISTS (
      SELECT 1 FROM public.obras_obra_empresa oe
      WHERE oe.obra_id = p_ancla_id AND oe.empresa_id = p_entidad_id AND oe.activo
    )
    WHEN p_tipo = 'persona' AND p_ancla_tipo = 'obra' THEN EXISTS (
      SELECT 1 FROM public.obras_obra_persona op
      WHERE op.obra_id = p_ancla_id AND op.persona_id = p_entidad_id AND op.activo
    )
    WHEN p_tipo = 'persona' AND p_ancla_tipo = 'empresa' THEN EXISTS (
      SELECT 1 FROM public.obras_persona_empresa pe
      WHERE pe.empresa_id = p_ancla_id AND pe.persona_id = p_entidad_id AND pe.activo
    )
    -- Una empresa no cuelga de otra empresa: el mismo corte que OB031 hace
    -- explícito en `obras_revocar_contextual`.
    ELSE false
  END;
$$;
REVOKE EXECUTE ON FUNCTION public.obras_ctx_vinculo_vivo(text, uuid, text, uuid) FROM PUBLIC;

-- La vigencia queda igual: mismo resultado, con el EXISTS del vínculo llamado
-- en vez de escrito. Se conserva la recursión de la rama empresa —verificada
-- en sql/092: no cicla, porque la llamada de adentro es sobre 'empresa' y esa
-- rama no vuelve a recursar.
CREATE OR REPLACE FUNCTION obras_ctx_vigente(
  p_tipo       text,
  p_entidad_id uuid,
  p_ancla_tipo text DEFAULT NULL,
  p_ancla_id   uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_tipo

    WHEN 'empresa' THEN EXISTS (
      SELECT 1 FROM public.obras_empresa_grant_contextual g
      WHERE g.empresa_id = p_entidad_id
        AND g.usuario_id = (select auth.uid())
        AND g.activo
        AND (p_ancla_tipo IS NULL OR (p_ancla_tipo = 'obra' AND g.obra_id = p_ancla_id))
        AND obras_puede_ver_obra(g.obra_id)
        AND obras_ctx_vinculo_vivo('empresa', g.empresa_id, 'obra', g.obra_id)
    )

    WHEN 'persona' THEN EXISTS (
      SELECT 1 FROM public.obras_persona_grant_contextual g
      WHERE g.persona_id = p_entidad_id
        AND g.usuario_id = (select auth.uid())
        AND g.activo
        AND (
          (g.obra_id IS NOT NULL
           AND (p_ancla_tipo IS NULL OR (p_ancla_tipo = 'obra' AND g.obra_id = p_ancla_id))
           AND obras_puede_ver_obra(g.obra_id)
           AND obras_ctx_vinculo_vivo('persona', g.persona_id, 'obra', g.obra_id))
          OR
          (g.empresa_id IS NOT NULL
           AND (p_ancla_tipo IS NULL OR (p_ancla_tipo = 'empresa' AND g.empresa_id = p_ancla_id))
           AND (obras_puede_ver_empresa(g.empresa_id)
                OR obras_ctx_vigente('empresa', g.empresa_id))
           AND obras_ctx_vinculo_vivo('persona', g.persona_id, 'empresa', g.empresa_id))
        )
    )

    ELSE false
  END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · La ficha de persona recupera su código
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_ficha_persona(
  p_persona_id uuid,
  p_ctx_tipo   text DEFAULT NULL,
  p_ctx_id     uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid, nombre text, apellido text, telefono text, whatsapp text, email text,
  observaciones text, creado_por uuid,
  created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ok boolean;
BEGIN
  v_ok := obras_puede_ver_persona(p_persona_id);

  IF NOT v_ok AND p_ctx_tipo IS NOT NULL AND p_ctx_id IS NOT NULL THEN
    v_ok := obras_ctx_vigente('persona', p_persona_id, p_ctx_tipo, p_ctx_id);
  END IF;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Sin acceso a esta persona' USING ERRCODE = 'OB009';
  END IF;

  INSERT INTO obras_accesos_persona (usuario_id, persona_id, contexto)
  VALUES (auth.uid(), p_persona_id, nullif(concat_ws(':', p_ctx_tipo, p_ctx_id::text), ''));

  RETURN QUERY
  SELECT p.id, p.nombre, p.apellido, p.telefono, p.whatsapp, p.email,
         p.observaciones, p.creado_por, p.created_at, p.updated_at
  FROM obras_personas p
  WHERE p.id = p_persona_id AND p.activo;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · La vista Compartido: sin filas muertas y sin links rotos
-- ─────────────────────────────────────────────────────────────────────────────

-- DROP y no REPLACE: cambia el RETURNS TABLE.
DROP FUNCTION IF EXISTS obras_compartidos_por_mi();

CREATE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE (
  tipo           text,
  entidad_id     uuid,
  entidad_nombre text,
  usuario_id     uuid,
  usuario_nombre text,
  origen_tipo    text,
  origen_id      uuid,
  origen_nombre  text,
  compartida_el  timestamptz,
  puedo_abrir    boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  -- Una obra la comparte su responsable, así que siempre la puede abrir.
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at, true
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE o.responsable_id = auth.uid() AND c.activo

  UNION ALL
  -- Un contextual lo lista quien manda sobre él: el dueño del contacto o el del
  -- ancla (sql/093). `usuario_id <> auth.uid()` saca las filas donde soy el
  -- receptor. `_vinculo_vivo` saca las que el estado 3 de transferir dejó
  -- activas sin vínculo debajo: no abren nada y simulaban un reparto.
  SELECT 'empresa'::text, g.empresa_id, e.razon_social, g.usuario_id, u.nombre,
         'obra'::text, g.obra_id,
         (SELECT nombre FROM obras WHERE id = g.obra_id),
         g.created_at,
         obras_puede_ver_empresa(g.empresa_id)
  FROM obras_empresa_grant_contextual g
  JOIN obras_empresas e ON e.id = g.empresa_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.activo AND g.usuario_id <> auth.uid()
    AND obras_ctx_autoridad('empresa', g.empresa_id, 'obra', g.obra_id)
    AND obras_ctx_vinculo_vivo('empresa', g.empresa_id, 'obra', g.obra_id)

  UNION ALL
  SELECT 'persona'::text, g.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         g.usuario_id, u.nombre,
         CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
         coalesce(g.obra_id, g.empresa_id),
         CASE WHEN g.obra_id IS NOT NULL
              THEN (SELECT nombre FROM obras WHERE id = g.obra_id)
              ELSE (SELECT razon_social FROM obras_empresas WHERE id = g.empresa_id) END,
         g.created_at,
         obras_puede_ver_persona(g.persona_id)
  FROM obras_persona_grant_contextual g
  JOIN obras_personas p ON p.id = g.persona_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.activo AND g.usuario_id <> auth.uid()
    AND obras_ctx_autoridad('persona', g.persona_id,
          CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
          coalesce(g.obra_id, g.empresa_id))
    AND obras_ctx_vinculo_vivo('persona', g.persona_id,
          CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
          coalesce(g.obra_id, g.empresa_id))

  ORDER BY 9 DESC
  LIMIT 500;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.obras_compartidos_por_mi() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.obras_compartidos_por_mi() TO authenticated;
