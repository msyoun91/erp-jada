-- Monedas, 2 de 2: tipos de cambio con fecha, moneda principal y consultas a MonedAPI.
-- Ficha y decisiones: decisiones/monedas.md. Esquema: db_schema/monedas.md. Test: sql/tests/monedas.sql.
--
-- Toda escritura pasa por funciones: un tipo de cambio vigente no se edita (un presupuesto se
-- recalcula con el de su fecha, decisiones/catalogo.md → Un presupuesto se recalcula como era), y
-- lo de MonedAPI lo guarda solo el servidor con service_role.

-- ============================================================
-- 1. Tablas
-- ============================================================
DO $$
BEGIN
  CREATE TYPE origen_tipo_cambio AS ENUM ('monedapi', 'manual');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- vigente_desde NULL: rojo de MonedAPI que espera confirmación. fecha es la del valor (updatedAt de
-- MonedAPI o la carga a mano); vigente_desde, desde cuándo se usa.
CREATE TABLE IF NOT EXISTS public.monedas_tipos_cambio (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moneda         moneda NOT NULL CONSTRAINT monedas_tipos_cambio_no_ars CHECK (moneda <> 'ARS'),
  valor          numeric(12,2) NOT NULL CHECK (valor > 0),
  fecha          timestamptz NOT NULL,
  origen         origen_tipo_cambio NOT NULL,
  vigente_desde  timestamptz,
  creado_por     uuid REFERENCES public.usuarios(id),
  confirmado_por uuid REFERENCES public.usuarios(id),
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS monedas_tipos_cambio_vigente
  ON public.monedas_tipos_cambio (moneda, vigente_desde DESC)
  WHERE activo AND vigente_desde IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS monedas_tipos_cambio_un_pendiente
  ON public.monedas_tipos_cambio (moneda)
  WHERE activo AND vigente_desde IS NULL;

CREATE TABLE IF NOT EXISTS public.monedas_principal (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moneda     moneda NOT NULL,
  creado_por uuid NOT NULL REFERENCES public.usuarios(id),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ok NULL: en curso.
CREATE TABLE IF NOT EXISTS public.monedas_consultas (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  forzada    boolean NOT NULL,
  ok         boolean,
  error      text,
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.monedas_tipos_cambio
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.monedas_principal
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.monedas_consultas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 2. RLS: el historial lo ve monedas_ver; lo vigente, todos, por monedas_hoy()
-- ============================================================
ALTER TABLE public.monedas_tipos_cambio ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monedas_principal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monedas_consultas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS monedas_tipos_cambio_select ON public.monedas_tipos_cambio;
CREATE POLICY monedas_tipos_cambio_select ON public.monedas_tipos_cambio
  FOR SELECT TO authenticated USING (public.tiene_permiso('monedas_ver'));

DROP POLICY IF EXISTS monedas_principal_select ON public.monedas_principal;
CREATE POLICY monedas_principal_select ON public.monedas_principal
  FOR SELECT TO authenticated USING (public.tiene_permiso('monedas_ver'));

DROP POLICY IF EXISTS monedas_consultas_select ON public.monedas_consultas;
CREATE POLICY monedas_consultas_select ON public.monedas_consultas
  FOR SELECT TO authenticated USING (public.tiene_permiso('monedas_ver'));

GRANT SELECT ON public.monedas_tipos_cambio, public.monedas_principal, public.monedas_consultas
  TO authenticated;

-- ============================================================
-- 3. Lectura: tipo de cambio a una fecha y conversión
-- ============================================================

-- Los tres niveles del costo (decisiones/catalogo.md → Versiones y aprobación), para subas y
-- bajas. Lo usan Monedas y el catálogo: vive una vez.
CREATE OR REPLACE FUNCTION public.nivel_cambio(p_anterior numeric, p_nuevo numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_anterior IS NULL OR p_anterior = 0 OR p_nuevo IS NULL THEN NULL
    WHEN abs(p_nuevo - p_anterior) / abs(p_anterior) >= 0.50 THEN 'rojo'
    WHEN abs(p_nuevo - p_anterior) / abs(p_anterior) >= 0.25 THEN 'naranja'
    WHEN abs(p_nuevo - p_anterior) / abs(p_anterior) >= 0.15 THEN 'amarillo'
  END;
$$;

-- DEFINER: los tipos de cambio son públicos y la función del precio la llama quien no tiene
-- monedas_ver (vendedor, cliente).
CREATE OR REPLACE FUNCTION public.monedas_tipo_cambio(p_moneda moneda, p_en timestamptz DEFAULT now())
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN p_moneda = 'ARS' THEN 1::numeric ELSE (
    SELECT t.valor FROM public.monedas_tipos_cambio t
    WHERE t.moneda = p_moneda AND t.activo AND t.vigente_desde <= p_en
    ORDER BY t.vigente_desde DESC
    LIMIT 1
  ) END;
$$;

CREATE OR REPLACE FUNCTION public.monedas_convertir(
  p_monto numeric, p_de moneda, p_a moneda, p_en timestamptz DEFAULT now()
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_de numeric;
  v_a  numeric;
BEGIN
  IF p_de = p_a THEN
    RETURN p_monto;
  END IF;
  v_de := public.monedas_tipo_cambio(p_de, p_en);
  v_a  := public.monedas_tipo_cambio(p_a, p_en);
  IF v_de IS NULL OR v_a IS NULL THEN
    RAISE EXCEPTION 'Sin tipo de cambio de % a esa fecha', CASE WHEN v_de IS NULL THEN p_de ELSE p_a END
      USING ERRCODE = 'MO001';
  END IF;
  RETURN p_monto * v_de / v_a;
END;
$$;

CREATE OR REPLACE FUNCTION public.monedas_principal_actual()
RETURNS moneda
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT p.moneda FROM public.monedas_principal p
    WHERE p.activo ORDER BY p.created_at DESC LIMIT 1
  ), 'ARS');
$$;

-- Lo que muestra la barra de menú a todo usuario (decisiones/monedas.md → Quién los ve), más
-- cuándo se pidió por última vez a MonedAPI, para saber si toca pedir de nuevo.
CREATE OR REPLACE FUNCTION public.monedas_hoy()
RETURNS TABLE (moneda moneda, valor numeric, fecha timestamptz, ultima_consulta timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.moneda, t.valor, t.fecha, (SELECT max(c.created_at) FROM public.monedas_consultas c)
  FROM unnest(enum_range(NULL::moneda)) AS m(moneda)
  LEFT JOIN LATERAL (
    SELECT x.valor, x.fecha FROM public.monedas_tipos_cambio x
    WHERE x.moneda = m.moneda AND x.activo AND x.vigente_desde IS NOT NULL
    ORDER BY x.vigente_desde DESC
    LIMIT 1
  ) t ON true
  WHERE m.moneda <> 'ARS';
$$;

-- Estado, no evento (decisiones/global/infra.md → Evento es fila, estado es consulta): se calcula
-- al mirar. Solo para quien puede corregir.
CREATE OR REPLACE FUNCTION public.monedas_avisos()
RETURNS TABLE (aviso text, moneda moneda, valor numeric, desde timestamptz)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT 'monedapi_falla', NULL::moneda, NULL::numeric, min(c.created_at)
  FROM public.monedas_consultas c
  WHERE c.ok = false
    AND c.created_at > coalesce((SELECT max(o.created_at) FROM public.monedas_consultas o WHERE o.ok), '-infinity')
    AND public.tiene_permiso('monedas_corregir')
  HAVING count(*) > 0

  UNION ALL

  SELECT 'por_confirmar', t.moneda, t.valor, t.created_at
  FROM public.monedas_tipos_cambio t
  WHERE t.activo AND t.vigente_desde IS NULL AND public.tiene_permiso('monedas_corregir')

  UNION ALL

  SELECT 'sin_actualizar', h.moneda, h.valor, h.fecha
  FROM public.monedas_hoy() h
  WHERE h.fecha < now() - interval '7 days' AND public.tiene_permiso('monedas_corregir');
$$;

-- Con quién y contra qué valor: el nivel se mide contra el vigente anterior.
CREATE OR REPLACE FUNCTION public.monedas_historial(p_moneda moneda, p_limite int DEFAULT 50)
RETURNS TABLE (id uuid, valor numeric, fecha timestamptz, origen origen_tipo_cambio,
               vigente_desde timestamptz, anterior numeric, nivel text, cargado_por text,
               confirmado_por text, activo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id, t.valor, t.fecha, t.origen, t.vigente_desde, a.valor,
         public.nivel_cambio(a.valor, t.valor), uc.nombre, uf.nombre, t.activo
  FROM public.monedas_tipos_cambio t
  LEFT JOIN LATERAL (
    SELECT p.valor FROM public.monedas_tipos_cambio p
    WHERE p.moneda = t.moneda AND p.activo AND p.vigente_desde IS NOT NULL
      AND p.vigente_desde < coalesce(t.vigente_desde, t.created_at)
    ORDER BY p.vigente_desde DESC
    LIMIT 1
  ) a ON true
  LEFT JOIN public.usuarios uc ON uc.id = t.creado_por
  LEFT JOIN public.usuarios uf ON uf.id = t.confirmado_por
  WHERE t.moneda = p_moneda AND public.tiene_permiso('monedas_ver')
  ORDER BY t.created_at DESC
  LIMIT greatest(coalesce(p_limite, 50), 1);
$$;

-- ============================================================
-- 4. Escritura por una persona
-- ============================================================

-- Corregir reemplaza el rojo de MonedAPI que esperaba confirmación, si había.
CREATE OR REPLACE FUNCTION public.monedas_corregir(
  p_moneda moneda, p_valor numeric, p_confirmar_rojo boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.tiene_permiso('monedas_corregir') THEN
    RAISE EXCEPTION 'Corregir un tipo de cambio requiere monedas_corregir' USING ERRCODE = '42501';
  END IF;
  IF NOT coalesce(p_confirmar_rojo, false)
     AND public.nivel_cambio(public.monedas_tipo_cambio(p_moneda), p_valor) = 'rojo' THEN
    RAISE EXCEPTION 'Cambia 50 %% o más contra el vigente: confirmalo' USING ERRCODE = 'MO002';
  END IF;

  UPDATE public.monedas_tipos_cambio SET activo = false
  WHERE moneda = p_moneda AND activo AND vigente_desde IS NULL;

  INSERT INTO public.monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde, creado_por)
  VALUES (p_moneda, p_valor, now(), 'manual', now(), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.monedas_confirmar(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tiene_permiso('monedas_corregir') THEN
    RAISE EXCEPTION 'Confirmar un tipo de cambio requiere monedas_corregir' USING ERRCODE = '42501';
  END IF;
  UPDATE public.monedas_tipos_cambio SET vigente_desde = now(), confirmado_por = auth.uid()
  WHERE id = p_id AND activo AND vigente_desde IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese valor ya no espera confirmación' USING ERRCODE = 'MO003';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.monedas_elegir_principal(p_moneda moneda)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tiene_permiso('monedas_principal') THEN
    RAISE EXCEPTION 'Elegir la moneda principal requiere monedas_principal' USING ERRCODE = '42501';
  END IF;
  IF p_moneda IS DISTINCT FROM public.monedas_principal_actual() THEN
    INSERT INTO public.monedas_principal (moneda, creado_por) VALUES (p_moneda, auth.uid());
  END IF;
END;
$$;

-- ============================================================
-- 5. Escritura de MonedAPI: solo service_role (decisiones/monedas.md → Tipos de cambio)
-- ============================================================

-- Una consulta por hora, o por minuto con el botón, en todo el sistema. NULL: no toca.
CREATE OR REPLACE FUNCTION public.monedas_reservar_consulta(p_forzada boolean)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('monedas_consultas'));
  IF EXISTS (
    SELECT 1 FROM public.monedas_consultas c
    WHERE c.created_at > now() - CASE WHEN p_forzada THEN interval '1 minute' ELSE interval '1 hour' END
  ) THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.monedas_consultas (forzada) VALUES (p_forzada) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.monedas_cerrar_consulta(p_id uuid, p_error text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.monedas_consultas SET ok = p_error IS NULL, error = p_error WHERE id = p_id;
$$;

-- Entra solo si es más nuevo que lo guardado (también que una corrección a mano). Rojo contra el
-- vigente: queda esperando confirmación y se sigue usando el vigente.
CREATE OR REPLACE FUNCTION public.monedas_guardar_monedapi(p_moneda moneda, p_valor numeric, p_fecha timestamptz)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_fecha <= (
    SELECT max(t.fecha) FROM public.monedas_tipos_cambio t WHERE t.moneda = p_moneda AND t.activo
  ) THEN
    RETURN NULL;
  END IF;

  UPDATE public.monedas_tipos_cambio SET activo = false
  WHERE moneda = p_moneda AND activo AND vigente_desde IS NULL;

  INSERT INTO public.monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde)
  VALUES (
    p_moneda, p_valor, p_fecha, 'monedapi',
    CASE WHEN public.nivel_cambio(public.monedas_tipo_cambio(p_moneda), p_valor) = 'rojo' THEN NULL ELSE now() END
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ============================================================
-- 6. Avisos: todo valor que entra por una persona, a los demás que pueden corregir
-- ============================================================
CREATE OR REPLACE FUNCTION public.monedas_tipos_cambio_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.notificar(
    u.id,
    CASE WHEN TG_OP = 'INSERT' THEN 'tipo_cambio_corregido' ELSE 'tipo_cambio_confirmado' END::tipo_notificacion,
    'monedas_tipos_cambio', NEW.id, auth.uid())
  FROM public.usuarios u
  WHERE u.activo AND public.usuario_tiene_permiso(u.id, 'monedas_corregir');
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS monedas_tipos_cambio_avisar_manual ON public.monedas_tipos_cambio;
CREATE TRIGGER monedas_tipos_cambio_avisar_manual
  AFTER INSERT ON public.monedas_tipos_cambio
  FOR EACH ROW WHEN (NEW.origen = 'manual')
  EXECUTE FUNCTION public.monedas_tipos_cambio_avisar();

DROP TRIGGER IF EXISTS monedas_tipos_cambio_avisar_confirmado ON public.monedas_tipos_cambio;
CREATE TRIGGER monedas_tipos_cambio_avisar_confirmado
  AFTER UPDATE OF confirmado_por ON public.monedas_tipos_cambio
  FOR EACH ROW WHEN (OLD.confirmado_por IS NULL AND NEW.confirmado_por IS NOT NULL)
  EXECUTE FUNCTION public.monedas_tipos_cambio_avisar();

-- ============================================================
-- 7. Privilegios de las funciones
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.monedas_tipo_cambio(moneda, timestamptz),
  public.monedas_convertir(numeric, moneda, moneda, timestamptz),
  public.monedas_principal_actual(),
  public.monedas_hoy(),
  public.monedas_avisos(),
  public.monedas_historial(moneda, int),
  public.monedas_corregir(moneda, numeric, boolean),
  public.monedas_confirmar(uuid),
  public.monedas_elegir_principal(moneda),
  public.monedas_reservar_consulta(boolean),
  public.monedas_cerrar_consulta(uuid, text),
  public.monedas_guardar_monedapi(moneda, numeric, timestamptz),
  public.monedas_tipos_cambio_avisar()
FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION
  public.monedas_reservar_consulta(boolean),
  public.monedas_cerrar_consulta(uuid, text),
  public.monedas_guardar_monedapi(moneda, numeric, timestamptz),
  public.monedas_tipos_cambio_avisar()
FROM authenticated;

GRANT EXECUTE ON FUNCTION
  public.monedas_tipo_cambio(moneda, timestamptz),
  public.monedas_convertir(numeric, moneda, moneda, timestamptz),
  public.monedas_principal_actual(),
  public.monedas_hoy(),
  public.monedas_avisos(),
  public.monedas_historial(moneda, int),
  public.monedas_corregir(moneda, numeric, boolean),
  public.monedas_confirmar(uuid),
  public.monedas_elegir_principal(moneda)
TO authenticated;

GRANT EXECUTE ON FUNCTION
  public.monedas_reservar_consulta(boolean),
  public.monedas_cerrar_consulta(uuid, text),
  public.monedas_guardar_monedapi(moneda, numeric, timestamptz)
TO service_role;

-- ============================================================
-- 8. Catálogo de permisos (decisiones/monedas.md → Ficha del módulo: no se delega, sin reglas)
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT 'monedas_ver', 'monedas', 'vista', 'Monedas', 1, false
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = 'monedas_ver' AND s.activo);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT f.codigo, 'monedas', 'funcion', f.nombre, f.orden, v.id, false
FROM public.submodulos v
CROSS JOIN (VALUES ('monedas_corregir', 'Corregir tipos de cambio', 1),
                   ('monedas_principal', 'Elegir la moneda principal', 2)) AS f(codigo, nombre, orden)
WHERE v.codigo = 'monedas_ver' AND v.activo
  AND NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = f.codigo AND s.activo);

-- ============================================================
-- 9. Notificaciones: entidad y rama en notificaciones_listar
-- ============================================================
ALTER TABLE public.usuario_notificaciones DROP CONSTRAINT usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad = ANY (ARRAY['equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos',
                              'tareas_plantillas', 'usuarios', 'obras', 'obras_participantes',
                              'contactos_personas', 'contactos_empresas', 'monedas_tipos_cambio']));

-- "$1.565,00": el motivo es texto y la campanita lo muestra tal cual.
CREATE OR REPLACE FUNCTION public.monedas_formato(p_valor numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '$' || translate(to_char(p_valor, 'FM999,999,999,990.00'), ',.', '.,');
$$;

CREATE OR REPLACE FUNCTION public.notificaciones_listar(p_limite int DEFAULT 30)
RETURNS TABLE (id uuid, tipo tipo_notificacion, etiqueta text, motivo text, actor text, destino text,
               destino_id uuid, leida boolean, created_at timestamptz)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH mias AS (
    SELECT n.*
    FROM usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo
    ORDER BY n.created_at DESC
    LIMIT greatest(coalesce(p_limite, 30), 1)
  ),
  resuelta AS (
    SELECT n.id AS notificacion_id,
           u.nombre AS etiqueta,
           NULL::text AS motivo,
           'mi_equipo'::text AS destino,
           m.usuario_id AS destino_id
    FROM mias n
    JOIN equipos_miembros m ON m.id = n.entidad_id AND m.activo
    JOIN usuarios u         ON u.id = m.usuario_id
    WHERE n.entidad = 'equipos_miembros'

    UNION ALL

    SELECT n.id,
           CASE WHEN n.tipo = 'delegador_designado' THEN e.nombre ELSE s.nombre END,
           NULL::text,
           CASE WHEN n.tipo = 'delegador_designado' THEN 'mi_equipo' ELSE s.modulo END,
           us.id
    FROM mias n
    JOIN usuario_submodulos us ON us.id = n.entidad_id AND us.activo
    JOIN submodulos s          ON s.id = us.submodulo_id
    LEFT JOIN equipos e        ON e.id = mi_equipo()
    WHERE n.entidad = 'usuario_submodulos'

    UNION ALL

    SELECT n.id,
           coalesce(t.titulo, x.titulo),
           CASE WHEN n.tipo = 'pedido_rechazado' THEN t.motivo_rechazo END,
           CASE WHEN t.id IS NOT NULL THEN 'tarea' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas t                 ON t.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas' AND (t.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id,
           coalesce(h.titulo, x.titulo),
           CASE WHEN n.tipo = 'plantilla_disparada' THEN etiqueta_registro(h.registro_ente, h.registro_id) END,
           CASE WHEN h.id IS NOT NULL THEN 'hilo' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas_hilos h           ON h.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas_hilos' AND (h.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, p.nombre, NULL::text, 'plantillas', p.id
    FROM mias n
    JOIN tareas_plantillas p ON p.id = n.entidad_id
    WHERE n.entidad = 'tareas_plantillas'

    UNION ALL

    SELECT n.id, o.nombre, NULL::text, 'obra', o.id
    FROM mias n
    JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obras'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma')

    UNION ALL

    SELECT n.id,
           coalesce(o.nombre, x.nombre),
           NULL::text,
           CASE WHEN o.id IS NOT NULL THEN 'obra' END,
           coalesce(o.id, x.obra_id)
    FROM mias n
    LEFT JOIN obras_avisos_salida() x ON x.notificacion_id = n.id
    LEFT JOIN obras_participantes p   ON p.id = n.entidad_id
    LEFT JOIN obras o                 ON o.id = coalesce(p.obra_id, x.obra_id)
    WHERE n.entidad = 'obras_participantes' AND n.tipo <> 'obra_misma_sumado'
      AND (o.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, c.nombre, NULL::text, 'persona', c.id
    FROM mias n
    JOIN contactos_personas c ON c.id = n.entidad_id
    WHERE n.entidad = 'contactos_personas'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma',
                         'persona_fusionada')

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN duplicados_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN contactos_fusion_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT n.id,
           a.nombre,
           c.cuantos || ' ' || CASE
             WHEN n.tipo = 'hilos_huerfanos' THEN
               CASE WHEN c.cuantos = 1 THEN 'hilo abierto' ELSE 'hilos abiertos' END
             WHEN n.tipo IN ('obras_huerfanas', 'obras_recibidas') THEN
               CASE WHEN c.cuantos = 1 THEN 'obra' ELSE 'obras' END
             ELSE
               CASE WHEN c.cuantos = 1 THEN 'persona' ELSE 'personas' END
           END,
           CASE n.tipo
             WHEN 'hilos_huerfanos' THEN 'tareas_todas'
             WHEN 'obras_huerfanas' THEN 'obras_todas'
             WHEN 'obras_recibidas' THEN 'obras'
             ELSE 'contactos'
           END,
           n.entidad_id
    FROM mias n
    CROSS JOIN LATERAL (
      SELECT CASE n.tipo
        WHEN 'hilos_huerfanos' THEN (
          SELECT count(*) FROM tareas_hilos h
          WHERE h.responsable_id = n.entidad_id AND h.activo AND h.estado = 'abierto')
        WHEN 'obras_huerfanas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.entidad_id AND o.activo)
        WHEN 'personas_huerfanas' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.entidad_id AND p.activo)
        WHEN 'obras_recibidas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.usuario_id AND o.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'obra' AND e.registro_id = o.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
        WHEN 'agenda_recibida' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.usuario_id AND p.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'persona' AND e.registro_id = p.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
      END AS cuantos
    ) c
    LEFT JOIN notificaciones_actores() a ON a.id = n.entidad_id
    WHERE n.entidad = 'usuarios' AND c.cuantos > 0

    UNION ALL

    SELECT n.id,
           t.moneda::text,
           concat_ws(' → ', monedas_formato(a.valor), monedas_formato(t.valor)),
           'monedas',
           t.id
    FROM mias n
    JOIN monedas_tipos_cambio t ON t.id = n.entidad_id
    LEFT JOIN LATERAL (
      SELECT p.valor FROM monedas_tipos_cambio p
      WHERE p.moneda = t.moneda AND p.activo AND p.vigente_desde < t.vigente_desde
      ORDER BY p.vigente_desde DESC
      LIMIT 1
    ) a ON true
    WHERE n.entidad = 'monedas_tipos_cambio'
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;
