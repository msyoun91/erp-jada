-- ============================================================
-- 028 — Agenda de Obras: funciones de negocio
--
-- Todo lo que no es un INSERT/UPDATE plano cubierto por RLS vive acá:
-- transferencia, desactivación, detección difusa de duplicados y la ficha de
-- persona con registro de acceso. `actions.ts` queda como glue.
--
-- Las que son SECURITY DEFINER lo son porque tienen que ver más de lo que ve
-- quien las llama (buscar duplicados entre obras ajenas) o escribir en una
-- tabla sin GRANT (los logs). Cada una verifica su propio permiso y devuelve
-- lo mínimo.
-- ============================================================

-- ============================================================
-- 1. Transferir una obra
--
-- El destino tiene que poder abrirla: transferirla a alguien sin `obras_ver`
-- la haría desaparecer para todos menos para quien transfiere.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir(p_obra_id uuid, p_a_usuario_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actual uuid;
BEGIN
  IF NOT tiene_permiso('obras_transferir') THEN
    RAISE EXCEPTION 'Sin permiso para transferir obras';
  END IF;

  SELECT responsable_id INTO v_actual FROM obras WHERE id = p_obra_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Obra inexistente o desactivada';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La obra ya es de ese usuario';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras';
  END IF;

  UPDATE obras SET responsable_id = p_a_usuario_id WHERE id = p_obra_id;

  INSERT INTO obras_transferencias (obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES (p_obra_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- ============================================================
-- 2. Desactivar / reactivar una obra
--
-- Permiso propio: cargar y corregir datos no es lo mismo que hacer
-- desaparecer una obra. `activo` no tiene GRANT justamente por esto.
-- Sin cascada sobre los vínculos: la obra desactivada se puede reactivar tal
-- como estaba, y las relaciones no se ven porque la obra no se lista.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_set_activo(p_obra_id uuid, p_activo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_desactivar') THEN
    RAISE EXCEPTION 'Sin permiso para desactivar obras';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM obras WHERE id = p_obra_id AND responsable_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'La obra no existe o no sos su responsable';
  END IF;

  UPDATE obras SET activo = p_activo WHERE id = p_obra_id;
END;
$$;

-- ============================================================
-- 3. Duplicados de obra — aviso ciego
--
-- Dos vendedores no pueden cargar el mismo edificio, pero tampoco pueden ver
-- las obras del otro. La salida es avisar sin mostrar: de una obra ajena se
-- devuelve el nombre del responsable y nada más — ni dirección, ni estado,
-- ni id. Alcanza para que el vendedor vaya a preguntar.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_obra(
  p_nombre     text,
  p_direccion  text DEFAULT NULL,
  p_localidad  text DEFAULT NULL
)
RETURNS TABLE (
  es_mia       boolean,
  obra_id      uuid,
  nombre       text,
  direccion    text,
  localidad    text,
  responsable  text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH candidatas AS (
    SELECT o.id, o.nombre, o.direccion, o.localidad, o.responsable_id,
           o.responsable_id = auth.uid() AS mia,
           greatest(
             extensions.similarity(o.nombre_norm, obras_normalizar(p_nombre)),
             CASE
               WHEN p_direccion IS NULL OR o.direccion_norm IS NULL THEN 0
               ELSE extensions.similarity(o.direccion_norm, obras_normalizar(p_direccion))
             END
           ) AS score
    FROM obras o
    WHERE o.activo
      AND (
        p_localidad IS NULL
        OR o.localidad_norm IS NULL
        OR o.localidad_norm = obras_normalizar(p_localidad)
      )
  )
  SELECT c.mia,
         CASE WHEN c.mia THEN c.id END,
         CASE WHEN c.mia THEN c.nombre END,
         CASE WHEN c.mia THEN c.direccion END,
         CASE WHEN c.mia THEN c.localidad END,
         u.nombre
  FROM candidatas c
  JOIN usuarios u ON u.id = c.responsable_id
  WHERE c.score >= 0.45 AND tiene_permiso('obras_ver')
  ORDER BY c.score DESC
  LIMIT 5;
$$;

-- ============================================================
-- 4. Duplicados de empresa
--
-- Las empresas son compartidas, así que acá no hay nada que ocultar.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_empresa(
  p_razon_social      text,
  p_nombre_comercial  text DEFAULT NULL
)
RETURNS TABLE (
  empresa_id        uuid,
  razon_social      text,
  nombre_comercial  text,
  localidad         text
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public
AS $$
  SELECT e.id, e.razon_social, e.nombre_comercial, e.localidad
  FROM obras_empresas e
  WHERE e.activo
    AND greatest(
      extensions.similarity(e.razon_social_norm, obras_normalizar(p_razon_social)),
      CASE
        WHEN p_nombre_comercial IS NULL OR e.nombre_comercial_norm IS NULL THEN 0
        ELSE extensions.similarity(e.nombre_comercial_norm, obras_normalizar(p_nombre_comercial))
      END
    ) >= 0.45
  ORDER BY extensions.similarity(e.razon_social_norm, obras_normalizar(p_razon_social)) DESC
  LIMIT 5;
$$;

-- ============================================================
-- 5. Duplicados de persona — identidad mínima
--
-- Devuelve que Juan Pérez ya existe y en qué empresa está, nunca su teléfono
-- ni su mail. Con eso el vendedor no lo carga de nuevo, y si lo necesita lo
-- vincula a su obra — que es lo que le da acceso al contacto, y queda
-- registrado. Buscar la agenda entera no revela la agenda entera.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_persona(
  p_nombre    text,
  p_apellido  text DEFAULT NULL,
  p_email     text DEFAULT NULL,
  p_telefono  text DEFAULT NULL
)
RETURNS TABLE (
  persona_id  uuid,
  nombre      text,
  apellido    text,
  empresa     text,
  coincide    text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT p.id, p.nombre, p.apellido,
         (
           SELECT e.razon_social
           FROM obras_persona_empresa pe
           JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo
           WHERE pe.persona_id = p.id AND pe.activo
           ORDER BY pe.es_principal DESC
           LIMIT 1
         ),
         CASE
           WHEN p.email_norm IS NOT NULL
            AND p.email_norm = nullif(lower(btrim(coalesce(p_email, ''))), '') THEN 'email'
           WHEN p.telefono_norm IS NOT NULL
            AND p.telefono_norm = obras_normalizar_telefono(p_telefono) THEN 'telefono'
           ELSE 'nombre'
         END
  FROM obras_personas p
  WHERE p.activo
    AND (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (
      (p.email_norm IS NOT NULL
        AND p.email_norm = nullif(lower(btrim(coalesce(p_email, ''))), ''))
      OR (p.telefono_norm IS NOT NULL
        AND p.telefono_norm = obras_normalizar_telefono(p_telefono))
      OR extensions.similarity(
           p.nombre_norm,
           obras_normalizar(p_nombre || ' ' || coalesce(p_apellido, ''))
         ) >= 0.55
    )
  LIMIT 5;
$$;

-- ============================================================
-- 6. Ficha de persona — sirve el contacto y deja rastro
--
-- Único camino por el que la app lee teléfono, whatsapp y email. Que sea el
-- único es lo que hace que el log sirva: 340 llamadas de un mismo usuario en
-- dos días es una consulta, no una sospecha.
-- SECURITY DEFINER porque escribe en el log (sin GRANT de INSERT), pero
-- re-verifica la visibilidad con la misma función que usa la policy.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_ficha_persona(p_persona_id uuid)
RETURNS TABLE (
  id             uuid,
  nombre         text,
  apellido       text,
  telefono       text,
  whatsapp       text,
  email          text,
  observaciones  text,
  creado_por     uuid,
  created_at     timestamptz,
  updated_at     timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT obras_puede_ver_persona(p_persona_id) THEN
    RAISE EXCEPTION 'Sin acceso a esta persona';
  END IF;

  INSERT INTO obras_accesos_persona (usuario_id, persona_id)
  VALUES (auth.uid(), p_persona_id);

  RETURN QUERY
  SELECT p.id, p.nombre, p.apellido, p.telefono, p.whatsapp, p.email,
         p.observaciones, p.creado_por, p.created_at, p.updated_at
  FROM obras_personas p
  WHERE p.id = p_persona_id AND p.activo;
END;
$$;

-- ============================================================
-- 7. GRANTs de ejecución
-- ============================================================
GRANT EXECUTE ON FUNCTION obras_transferir(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_set_activo(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_duplicados_obra(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_duplicados_empresa(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_duplicados_persona(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_ficha_persona(uuid) TO authenticated;
