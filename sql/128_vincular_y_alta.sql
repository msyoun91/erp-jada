-- sql/128 — vincular: buscar o crear en el panel, y el alta de obra con
-- "¿Quién?".
--
-- `contactos_vinculables`: lo que quien busca puede vincular (sus personas,
-- las empresas de su equipo). `contactos_crear_y_vincular`: crea la persona
-- (con su empresa, existente o nueva) o la empresa y la vincula, todo o nada.
-- `obras_alta`: la obra y, con origen referente, su "¿Quién?", todo o nada.
-- Todas INVOKER: las reglas son las policies y los triggers de `sql/126` y
-- `sql/127`, y el alta de la obra emite como quien la carga (dispara).
-- Las parecidas ("Ya la tenés", el aviso a ciegas) son del tramo 3.
-- Decisiones: `decisiones/contactos.md` → *Vincular: buscar o crear*,
-- `decisiones/obras.md` → *Con origen "referente", el alta pregunta quién*.
-- Verificado con `sql/tests/obras_alta.sql`.

-- ============================================================
-- 1. contactos_vinculables — el buscador del panel
-- ============================================================
-- Es la regla de quién vincula (`contactos_vinculos_validar`) como filtro:
-- `buscar_registros` devuelve lo que se ve, y ver no es poder vincular. De la
-- persona, su empresa actual si se la ve, para distinguir homónimos.
CREATE OR REPLACE FUNCTION public.contactos_vinculables(p_texto text)
RETURNS TABLE (tipo text, id uuid, nombre text, detalle text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(btrim(p_texto)) AS t
    WHERE length(btrim(p_texto)) >= 2
  ),
  encontrados AS (
    SELECT 'persona'::text AS tipo, p.id, p.nombre,
           (SELECT e.nombre
            FROM public.contactos_persona_empresa pe
            JOIN public.contactos_empresas e ON e.id = pe.empresa_id
            WHERE pe.persona_id = p.id AND pe.activo AND pe.hasta IS NULL
            ORDER BY pe.desde DESC
            LIMIT 1) AS detalle,
           strpos(lower(p.nombre), q.t) AS pos
    FROM q
    JOIN public.contactos_personas p
      ON p.activo AND p.responsable_id = (select auth.uid()) AND strpos(lower(p.nombre), q.t) > 0
    UNION ALL
    SELECT 'empresa', e.id, e.nombre, NULL, strpos(lower(e.nombre), q.t)
    FROM q
    JOIN public.contactos_empresas e
      ON e.activo
     AND (e.equipo_id = public.mi_equipo() OR (e.equipo_id IS NULL AND e.creado_por = (select auth.uid())))
     AND strpos(lower(e.nombre), q.t) > 0
  )
  SELECT tipo, id, nombre, detalle
  FROM encontrados
  ORDER BY pos <> 1, nombre
  LIMIT 15;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_vinculables(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_vinculables(text) TO authenticated;

-- ============================================================
-- 2. contactos_crear_y_vincular — si no está, se crea y se vincula
-- ============================================================
-- Persona: con su empresa opcional, elegida (`p_empresa_id`) o nueva con solo
-- el nombre (`p_empresa_nombre`), y el cargo. Empresa: sin empresa ni cargo.
-- Los ids se generan antes: sin RETURNING, la RLS de SELECT no se interpone
-- (GUIDE_DB → *Trampas de RLS*). Devuelve el id del contacto creado.
CREATE OR REPLACE FUNCTION public.contactos_crear_y_vincular(
  p_ente text,
  p_registro uuid,
  p_roles text[],
  p_tipo text,
  p_nombre text,
  p_telefono text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_empresa_id uuid DEFAULT NULL,
  p_empresa_nombre text DEFAULT NULL,
  p_cargo text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_contacto uuid := gen_random_uuid();
  v_empresa uuid := p_empresa_id;
BEGIN
  IF p_tipo = 'persona' THEN
    IF p_empresa_id IS NOT NULL AND p_empresa_nombre IS NOT NULL THEN
      RAISE EXCEPTION 'La empresa se elige o se crea, no las dos' USING ERRCODE = 'CO019';
    END IF;

    INSERT INTO public.contactos_personas (id, nombre, telefono, email)
    VALUES (v_contacto, p_nombre, p_telefono, p_email);

    IF p_empresa_nombre IS NOT NULL THEN
      v_empresa := gen_random_uuid();
      INSERT INTO public.contactos_empresas (id, nombre) VALUES (v_empresa, p_empresa_nombre);
    END IF;

    IF v_empresa IS NOT NULL THEN
      INSERT INTO public.contactos_persona_empresa (persona_id, empresa_id, cargo)
      VALUES (v_contacto, v_empresa, nullif(btrim(p_cargo), ''));
    END IF;

    INSERT INTO public.contactos_vinculos (persona_id, ente, registro_id, roles)
    VALUES (v_contacto, p_ente, p_registro, p_roles);
  ELSIF p_tipo = 'empresa' THEN
    IF num_nonnulls(p_empresa_id, p_empresa_nombre, p_cargo) > 0 THEN
      RAISE EXCEPTION 'Una empresa no lleva empresa ni cargo' USING ERRCODE = 'CO019';
    END IF;

    INSERT INTO public.contactos_empresas (id, nombre, telefono, email)
    VALUES (v_contacto, p_nombre, p_telefono, p_email);

    INSERT INTO public.contactos_vinculos (empresa_id, ente, registro_id, roles)
    VALUES (v_contacto, p_ente, p_registro, p_roles);
  ELSE
    RAISE EXCEPTION 'Se crea una persona o una empresa' USING ERRCODE = 'CO019';
  END IF;

  RETURN v_contacto;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_crear_y_vincular(text, uuid, text[], text, text, text, text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_crear_y_vincular(text, uuid, text[], text, text, text, text, uuid, text, text) TO authenticated;

-- ============================================================
-- 3. obras_alta — la obra y su "¿Quién?"
-- ============================================================
-- "¿Quién?" es uno: una persona o empresa existente, o una nueva (tipo,
-- nombre, teléfono, email; sin empresa: ya es el nivel anidado). Se vincula
-- con rol referente, y solo si el origen es referente.
CREATE OR REPLACE FUNCTION public.obras_alta(
  p_nombre text,
  p_direccion text,
  p_origen origen_obra,
  p_tipo tipo_obra,
  p_localidad text DEFAULT NULL,
  p_notas text DEFAULT NULL,
  p_compra_estimada date DEFAULT NULL,
  p_estado estado_obra DEFAULT 'idea',
  p_quien_persona uuid DEFAULT NULL,
  p_quien_empresa uuid DEFAULT NULL,
  p_quien_nuevo_tipo text DEFAULT NULL,
  p_quien_nuevo_nombre text DEFAULT NULL,
  p_quien_nuevo_telefono text DEFAULT NULL,
  p_quien_nuevo_email text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_obra uuid := gen_random_uuid();
  v_quien int := num_nonnulls(p_quien_persona, p_quien_empresa, p_quien_nuevo_tipo);
BEGIN
  IF v_quien > 1 THEN
    RAISE EXCEPTION '"¿Quién?" es una sola persona o empresa' USING ERRCODE = 'OB017';
  END IF;
  IF v_quien = 1 AND p_origen <> 'referente' THEN
    RAISE EXCEPTION '"¿Quién?" es para una obra que trae un referente' USING ERRCODE = 'OB017';
  END IF;

  INSERT INTO public.obras (id, nombre, direccion, localidad, notas, origen, tipo, compra_estimada, estado)
  VALUES (v_obra, p_nombre, p_direccion, p_localidad, p_notas, p_origen, p_tipo, p_compra_estimada, p_estado);

  IF p_quien_persona IS NOT NULL OR p_quien_empresa IS NOT NULL THEN
    INSERT INTO public.contactos_vinculos (persona_id, empresa_id, ente, registro_id, roles)
    VALUES (p_quien_persona, p_quien_empresa, 'obra', v_obra, '{referente}');
  ELSIF p_quien_nuevo_tipo IS NOT NULL THEN
    PERFORM public.contactos_crear_y_vincular(
      'obra', v_obra, '{referente}', p_quien_nuevo_tipo,
      p_quien_nuevo_nombre, p_quien_nuevo_telefono, p_quien_nuevo_email
    );
  END IF;

  RETURN v_obra;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_alta(text, text, origen_obra, tipo_obra, text, text, date, estado_obra, uuid, uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_alta(text, text, origen_obra, tipo_obra, text, text, date, estado_obra, uuid, uuid, text, text, text, text) TO authenticated;
