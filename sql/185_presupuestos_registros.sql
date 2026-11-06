-- Presupuestos, tramo 1: permisos, configuración, el presupuesto (ente), sus versiones y secciones.
-- Ficha y decisiones: decisiones/presupuestos.md. Esquema: db_schema/presupuestos.md.
-- Después: renglones y precio (tramo 2), ciclo de la versión (3), aprobar, rechazar y la obra (4), avisos (5).
-- Errores, clase PR: PR001 un presupuesto publicado no se desactiva · PR002 lo desactivado no vuelve ·
-- PR003 el presupuesto no admite versiones · PR004 variante que no sigue · PR005 la versión no está en borrador ·
-- PR006 la única versión no se descarta · PR007 la obra tiene presupuestos.

-- ============================================================
-- 1. Permisos
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT v.codigo, 'presupuestos', 'vista', v.nombre, v.orden, v.delegable
FROM (VALUES
  ('presupuestos_ver',           'Presupuestos',     1, true),
  ('presupuestos_revision',      'Revisión técnica', 2, true),
  ('presupuestos_configuracion', 'Configuración',    3, false)
) AS v (codigo, nombre, orden, delegable)
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = v.codigo AND s.activo);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT f.codigo, 'presupuestos', 'funcion', f.nombre, f.orden, v.id, f.delegable
FROM (VALUES
  ('presupuestos_armar',             'Armar',             1, 'presupuestos_ver',      true),
  ('presupuestos_autorizar',         'Autorizar',         2, 'presupuestos_ver',      false),
  ('presupuestos_administrar',       'Administrar',       3, 'presupuestos_ver',      false),
  ('presupuestos_autorizar_tecnica', 'Autorizar alertas', 1, 'presupuestos_revision', false)
) AS f (codigo, nombre, orden, vista, delegable)
JOIN public.submodulos v ON v.codigo = f.vista AND v.activo
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = f.codigo AND s.activo);

INSERT INTO public.submodulo_reglas (submodulo_id, otro_id, tipo)
SELECT a.id, b.id, 'requiere'
FROM (VALUES
  ('presupuestos_ver',         'obras_ver'),
  ('presupuestos_administrar', 'obras_administrar')
) AS r (submodulo, otro)
JOIN public.submodulos a ON a.codigo = r.submodulo AND a.activo
JOIN public.submodulos b ON b.codigo = r.otro AND b.activo
WHERE NOT EXISTS (
  SELECT 1 FROM public.submodulo_reglas x
  WHERE x.activo AND x.submodulo_id = a.id AND x.otro_id = b.id
);

-- ============================================================
-- 2. Enums
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.estado_presupuesto AS ENUM ('borrador', 'publicado', 'aprobado', 'rechazado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.estado_version_presupuesto AS ENUM ('borrador', 'en_revision', 'publicado', 'obsoleto');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 3. Quién ve y quién arma: la obra decide
-- ============================================================
-- Ve: quien ve la obra, con presupuestos_ver; administrar, todos. No mira `activo` del presupuesto:
-- desactivarlo es un UPDATE directo, y la fila nueva tiene que pasar la policy de SELECT.
CREATE OR REPLACE FUNCTION public.presupuestos_ve_de(p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'presupuestos_ver')
    AND (
      public.usuario_tiene_permiso(p_usuario, 'presupuestos_administrar')
      OR EXISTS (
        SELECT 1 FROM public.obras o
        WHERE o.id = p_obra
          AND public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, p_usuario)
      )
    );
$$;

-- Arma: quien trabaja la obra, con presupuestos_armar; administrar, en todas.
CREATE OR REPLACE FUNCTION public.presupuestos_arma_de(p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'presupuestos_ver')
    AND (
      public.usuario_tiene_permiso(p_usuario, 'presupuestos_administrar')
      OR (public.usuario_tiene_permiso(p_usuario, 'presupuestos_armar') AND public.obras_trabaja_de(p_obra, p_usuario))
    );
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_ve_de(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.presupuestos_arma_de(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_ve(p_obra uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.presupuestos_ve_de(p_obra, auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.presupuestos_arma(p_obra uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.presupuestos_arma_de(p_obra, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_ve(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_ve(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.presupuestos_arma(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_arma(uuid) TO authenticated;

-- ============================================================
-- 4. Configuración: una fila vigente; cambiar crea otra y desactiva la anterior
-- ============================================================
CREATE TABLE IF NOT EXISTS public.presupuestos_configuracion (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tope_descuento numeric(5,2) NOT NULL CHECK (tope_descuento >= 0 AND tope_descuento <= 100),
  plazo_dias integer NOT NULL CHECK (plazo_dias BETWEEN 1 AND 365),
  creado_por uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_configuracion_vigente
  ON public.presupuestos_configuracion (activo) WHERE activo;

ALTER TABLE public.presupuestos_configuracion ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_configuracion;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_configuracion
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_configuracion_select ON public.presupuestos_configuracion;
CREATE POLICY presupuestos_configuracion_select ON public.presupuestos_configuracion FOR SELECT
  USING (public.tiene_permiso('presupuestos_ver') OR public.tiene_permiso('presupuestos_configuracion'));
DROP POLICY IF EXISTS presupuestos_configuracion_insert ON public.presupuestos_configuracion;
CREATE POLICY presupuestos_configuracion_insert ON public.presupuestos_configuracion FOR INSERT
  WITH CHECK (public.tiene_permiso('presupuestos_configuracion'));
DROP POLICY IF EXISTS presupuestos_configuracion_update ON public.presupuestos_configuracion;
CREATE POLICY presupuestos_configuracion_update ON public.presupuestos_configuracion FOR UPDATE
  USING (public.tiene_permiso('presupuestos_configuracion'));

GRANT SELECT ON public.presupuestos_configuracion TO authenticated;
GRANT INSERT (id, tope_descuento, plazo_dias) ON public.presupuestos_configuracion TO authenticated;
GRANT UPDATE (activo) ON public.presupuestos_configuracion TO authenticated;

-- Lo desactivado no vuelve, en las cuatro tablas del módulo.
CREATE OR REPLACE FUNCTION public.presupuestos_no_reactivar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT OLD.activo AND NEW.activo THEN
    RAISE EXCEPTION 'Lo desactivado no vuelve' USING ERRCODE = 'PR002';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_no_reactivar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_configuracion_no_reactivar ON public.presupuestos_configuracion;
CREATE TRIGGER presupuestos_configuracion_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos_configuracion
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

CREATE OR REPLACE FUNCTION public.presupuestos_configurar(p_tope numeric, p_plazo integer)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  IF NOT public.tiene_permiso('presupuestos_configuracion') THEN
    RAISE EXCEPTION 'Sin permiso para configurar Presupuestos' USING ERRCODE = '42501';
  END IF;
  UPDATE public.presupuestos_configuracion SET activo = false WHERE activo;
  INSERT INTO public.presupuestos_configuracion (id, tope_descuento, plazo_dias) VALUES (v_id, p_tope, p_plazo);
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer) TO authenticated;

-- ============================================================
-- 5. presupuestos — ente `presupuesto`
-- ============================================================
CREATE SEQUENCE IF NOT EXISTS public.presupuestos_numero_seq;

CREATE TABLE IF NOT EXISTS public.presupuestos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  numero integer NOT NULL DEFAULT nextval('public.presupuestos_numero_seq'),
  codigo text GENERATED ALWAYS AS ('P-' || lpad(numero::text, greatest(4, length(numero::text)), '0')) STORED,
  nombre text NOT NULL CHECK (char_length(btrim(nombre)) BETWEEN 1 AND 200),
  obra_id uuid NOT NULL REFERENCES public.obras(id),
  estado public.estado_presupuesto NOT NULL DEFAULT 'borrador',
  creado_por uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER SEQUENCE public.presupuestos_numero_seq OWNED BY public.presupuestos.numero;
GRANT USAGE ON SEQUENCE public.presupuestos_numero_seq TO authenticated;

-- Lo que impide reutilizar un número es el correlativo y que nadie escribe la columna, no este índice.
CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_numero_unico ON public.presupuestos (numero) WHERE activo;
CREATE INDEX IF NOT EXISTS presupuestos_obra ON public.presupuestos (obra_id);

ALTER TABLE public.presupuestos ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_select ON public.presupuestos;
CREATE POLICY presupuestos_select ON public.presupuestos FOR SELECT
  USING (public.presupuestos_ve(obra_id));
DROP POLICY IF EXISTS presupuestos_insert ON public.presupuestos;
CREATE POLICY presupuestos_insert ON public.presupuestos FOR INSERT
  WITH CHECK (public.presupuestos_arma(obra_id));
DROP POLICY IF EXISTS presupuestos_update ON public.presupuestos;
CREATE POLICY presupuestos_update ON public.presupuestos FOR UPDATE
  USING (activo AND public.presupuestos_arma(obra_id))
  WITH CHECK (public.presupuestos_arma(obra_id));

GRANT SELECT ON public.presupuestos TO authenticated;
GRANT INSERT (id, nombre, obra_id) ON public.presupuestos TO authenticated;
GRANT UPDATE (nombre, activo) ON public.presupuestos TO authenticated;

-- Se desactiva solo si nunca se publicó: lo publicado ya movió la obra, y se aprueba o se rechaza.
CREATE OR REPLACE FUNCTION public.presupuestos_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.activo AND NOT NEW.activo AND OLD.estado <> 'borrador' THEN
    RAISE EXCEPTION 'Un presupuesto publicado no se desactiva: se aprueba o se rechaza' USING ERRCODE = 'PR001';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_al_editar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_al_editar ON public.presupuestos;
CREATE TRIGGER presupuestos_al_editar
  BEFORE UPDATE OF activo ON public.presupuestos
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_al_editar();

DROP TRIGGER IF EXISTS presupuestos_no_reactivar ON public.presupuestos;
CREATE TRIGGER presupuestos_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

-- ============================================================
-- 6. presupuestos_versiones
-- ============================================================
CREATE TABLE IF NOT EXISTS public.presupuestos_versiones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  presupuesto_id uuid NOT NULL REFERENCES public.presupuestos(id),
  numero integer NOT NULL,
  variante integer NOT NULL CHECK (variante >= 1),
  variante_nombre text CHECK (char_length(btrim(variante_nombre)) BETWEEN 1 AND 100),
  iva_discriminado boolean NOT NULL DEFAULT true,
  estado public.estado_version_presupuesto NOT NULL DEFAULT 'borrador',
  creado_por uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (presupuesto_id, numero)
);

CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_versiones_una_abierta
  ON public.presupuestos_versiones (presupuesto_id, variante) WHERE activo AND estado IN ('borrador', 'en_revision');
CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_versiones_una_publicada
  ON public.presupuestos_versiones (presupuesto_id, variante) WHERE activo AND estado = 'publicado';

ALTER TABLE public.presupuestos_versiones ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_versiones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_versiones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_versiones_select ON public.presupuestos_versiones;
CREATE POLICY presupuestos_versiones_select ON public.presupuestos_versiones FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.id = presupuesto_id));
DROP POLICY IF EXISTS presupuestos_versiones_insert ON public.presupuestos_versiones;
CREATE POLICY presupuestos_versiones_insert ON public.presupuestos_versiones FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.presupuestos p
    WHERE p.id = presupuesto_id AND p.activo AND public.presupuestos_arma(p.obra_id)));
DROP POLICY IF EXISTS presupuestos_versiones_update ON public.presupuestos_versiones;
CREATE POLICY presupuestos_versiones_update ON public.presupuestos_versiones FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.presupuestos p
    WHERE p.id = presupuesto_id AND p.activo AND public.presupuestos_arma(p.obra_id)));

GRANT SELECT ON public.presupuestos_versiones TO authenticated;
GRANT INSERT (id, presupuesto_id, variante, variante_nombre, iva_discriminado) ON public.presupuestos_versiones TO authenticated;
GRANT UPDATE (variante_nombre, iva_discriminado, activo) ON public.presupuestos_versiones TO authenticated;

-- Al crear: el número, contando las descartadas, y la variante, una que existe o la siguiente.
-- Al editar: solo en borrador; descartar, solo un borrador y nunca la única versión.
CREATE OR REPLACE FUNCTION public.presupuestos_versiones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_presupuesto public.presupuestos;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO v_presupuesto FROM public.presupuestos WHERE id = NEW.presupuesto_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
    END IF;
    IF NOT v_presupuesto.activo OR v_presupuesto.estado NOT IN ('borrador', 'publicado') THEN
      RAISE EXCEPTION 'El presupuesto % no admite versiones: está %', v_presupuesto.codigo,
        CASE WHEN NOT v_presupuesto.activo THEN 'desactivado' ELSE v_presupuesto.estado::text END
        USING ERRCODE = 'PR003';
    END IF;
    SELECT coalesce(max(v.numero), 0) + 1 INTO NEW.numero
    FROM public.presupuestos_versiones v WHERE v.presupuesto_id = NEW.presupuesto_id;
    IF NEW.variante > (SELECT coalesce(max(v.variante), 0) + 1
                       FROM public.presupuestos_versiones v WHERE v.presupuesto_id = NEW.presupuesto_id) THEN
      RAISE EXCEPTION 'La variante % no sigue a las que tiene el presupuesto', NEW.variante USING ERRCODE = 'PR004';
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.variante_nombre, NEW.iva_discriminado) IS DISTINCT FROM (OLD.variante_nombre, OLD.iva_discriminado)
     AND OLD.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;

  IF OLD.activo AND NOT NEW.activo THEN
    IF OLD.estado <> 'borrador' THEN
      RAISE EXCEPTION 'Solo se descarta un borrador' USING ERRCODE = 'PR005';
    END IF;
    PERFORM 1 FROM public.presupuestos WHERE id = OLD.presupuesto_id FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM public.presupuestos_versiones v
                   WHERE v.presupuesto_id = OLD.presupuesto_id AND v.activo AND v.id <> OLD.id) THEN
      RAISE EXCEPTION 'Es la única versión del presupuesto: se desactiva el presupuesto' USING ERRCODE = 'PR006';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_versiones_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_versiones_validar ON public.presupuestos_versiones;
CREATE TRIGGER presupuestos_versiones_validar
  BEFORE INSERT OR UPDATE ON public.presupuestos_versiones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_versiones_validar();

DROP TRIGGER IF EXISTS presupuestos_versiones_no_reactivar ON public.presupuestos_versiones;
CREATE TRIGGER presupuestos_versiones_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos_versiones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

-- ============================================================
-- 7. presupuestos_secciones — nombre, moneda y alícuota
-- ============================================================
CREATE TABLE IF NOT EXISTS public.presupuestos_secciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.presupuestos_versiones(id),
  nombre text NOT NULL CHECK (char_length(btrim(nombre)) BETWEEN 1 AND 100),
  moneda public.moneda NOT NULL,
  alicuota numeric(3,1) NOT NULL CHECK (alicuota IN (0, 10.5, 21)),
  orden integer NOT NULL DEFAULT 0,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_secciones_nombre
  ON public.presupuestos_secciones (version_id, lower(btrim(nombre))) WHERE activo;

ALTER TABLE public.presupuestos_secciones ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_secciones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_secciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_secciones_select ON public.presupuestos_secciones;
CREATE POLICY presupuestos_secciones_select ON public.presupuestos_secciones FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos_versiones v WHERE v.id = version_id));
DROP POLICY IF EXISTS presupuestos_secciones_insert ON public.presupuestos_secciones;
CREATE POLICY presupuestos_secciones_insert ON public.presupuestos_secciones FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = version_id AND p.activo AND public.presupuestos_arma(p.obra_id)));
DROP POLICY IF EXISTS presupuestos_secciones_update ON public.presupuestos_secciones;
CREATE POLICY presupuestos_secciones_update ON public.presupuestos_secciones FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = version_id AND p.activo AND public.presupuestos_arma(p.obra_id)));

GRANT SELECT ON public.presupuestos_secciones TO authenticated;
GRANT INSERT (id, version_id, nombre, moneda, alicuota, orden) ON public.presupuestos_secciones TO authenticated;
GRANT UPDATE (nombre, moneda, alicuota, orden, activo) ON public.presupuestos_secciones TO authenticated;

-- Solo en un borrador activo. FOR SHARE: no entra una edición mientras la versión se envía.
CREATE OR REPLACE FUNCTION public.presupuestos_secciones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_version public.presupuestos_versiones;
BEGIN
  SELECT * INTO v_version FROM public.presupuestos_versiones WHERE id = NEW.version_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  IF NOT v_version.activo OR v_version.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_secciones_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_secciones_validar ON public.presupuestos_secciones;
CREATE TRIGGER presupuestos_secciones_validar
  BEFORE INSERT OR UPDATE ON public.presupuestos_secciones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_secciones_validar();

DROP TRIGGER IF EXISTS presupuestos_secciones_no_reactivar ON public.presupuestos_secciones;
CREATE TRIGGER presupuestos_secciones_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos_secciones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

-- ============================================================
-- 8. Alta: el presupuesto con su v1 y una sección
-- ============================================================
CREATE OR REPLACE FUNCTION public.presupuestos_alta(p_obra uuid, p_nombre text, p_moneda public.moneda,
                                                    p_alicuota numeric, p_seccion text DEFAULT 'General')
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_version uuid := gen_random_uuid();
BEGIN
  IF NOT public.presupuestos_arma(p_obra) THEN
    RAISE EXCEPTION 'No armás presupuestos en esta obra' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.presupuestos (id, nombre, obra_id) VALUES (v_id, btrim(p_nombre), p_obra);
  INSERT INTO public.presupuestos_versiones (id, presupuesto_id, variante) VALUES (v_version, v_id, 1);
  INSERT INTO public.presupuestos_secciones (version_id, nombre, moneda, alicuota)
  VALUES (v_version, btrim(p_seccion), p_moneda, p_alicuota);
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_alta(uuid, text, public.moneda, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_alta(uuid, text, public.moneda, numeric, text) TO authenticated;

-- ============================================================
-- 9. La obra no se desactiva con presupuestos activos (decisiones/presupuestos.md → Efectos en la obra)
-- ============================================================
-- DEFINER: un presupuesto que quien desactiva no ve también la sostiene.
CREATE OR REPLACE FUNCTION public.presupuestos_obra_desactivar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.activo AND NOT NEW.activo
     AND EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = NEW.id AND p.activo) THEN
    RAISE EXCEPTION 'La obra tiene presupuestos activos y no se desactiva' USING ERRCODE = 'PR007';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_obra_desactivar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_obra_desactivar ON public.obras;
CREATE TRIGGER presupuestos_obra_desactivar
  BEFORE UPDATE OF activo ON public.obras
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_obra_desactivar();

-- ============================================================
-- 10. Ente, eventos y ramas de las genéricas
-- ============================================================
-- Dueño para el disparo: quien lo creó (corren sus plantillas). `alta` pasa por presupuestos_alta, INVOKER.
INSERT INTO public.entes (codigo, modulo, submodulo, estados, datos, roles, ruta, tabla, disparos, dueno)
VALUES ('presupuesto', 'presupuestos', 'presupuestos_ver', 'estado_presupuesto', '{codigo,nombre}', '{}',
        '/presupuestos/{id}', 'public.presupuestos', '{alta,estado}', 'creado_por')
ON CONFLICT (codigo) DO NOTHING;

DROP TRIGGER IF EXISTS emitir_eventos ON public.presupuestos;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON public.presupuestos
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('presupuesto');

-- "P-0142 · Nombre" si quien pregunta lo ve (la RLS decide).
CREATE OR REPLACE FUNCTION public.presupuestos_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'presupuesto' THEN (SELECT codigo || ' · ' || nombre FROM public.presupuestos WHERE id = p_id)
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_etiqueta(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_etiqueta(text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.presupuestos_ve_de(p.obra_id, p_usuario)
  FROM public.presupuestos p
  WHERE p.id = p_id AND p_tipo = 'presupuesto';
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_puede_abrir(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Por código o nombre, los activos que quien busca ve; la obra de subtítulo.
CREATE OR REPLACE FUNCTION public.presupuestos_buscar(p_texto text)
RETURNS TABLE(tipo text, id uuid, titulo text, subtitulo text)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(btrim(p_texto)) AS t
    WHERE length(btrim(p_texto)) >= 2
  )
  SELECT 'presupuesto'::text, p.id, p.codigo || ' · ' || p.nombre, o.nombre
  FROM q
  JOIN public.presupuestos p
    ON p.activo AND (strpos(lower(p.codigo), q.t) > 0 OR strpos(lower(p.nombre), q.t) > 0)
  LEFT JOIN public.obras o ON o.id = p.obra_id
  ORDER BY p.created_at DESC
  LIMIT 15;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_buscar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_buscar(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.etiqueta_registro(p_ente text, p_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE e.modulo
    WHEN 'tareas'       THEN public.tareas_etiqueta(p_ente, p_id)
    WHEN 'obras'        THEN public.obras_etiqueta(p_ente, p_id)
    WHEN 'contactos'    THEN public.contactos_etiqueta(p_ente, p_id)
    WHEN 'presupuestos' THEN public.presupuestos_etiqueta(p_ente, p_id)
  END
  FROM public.entes e
  WHERE e.codigo = p_ente;
$function$;

CREATE OR REPLACE FUNCTION public.puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'tareas'       THEN public.tareas_puede_abrir(p_ente, p_id, p_usuario)
      WHEN 'obras'        THEN public.obras_puede_abrir(p_ente, p_id, p_usuario)
      WHEN 'contactos'    THEN public.contactos_puede_abrir(p_ente, p_id, p_usuario)
      WHEN 'presupuestos' THEN public.presupuestos_puede_abrir(p_ente, p_id, p_usuario)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$function$;

CREATE OR REPLACE FUNCTION public.buscar_registros(p_modulo text, p_texto text)
 RETURNS TABLE(ente text, registro_id uuid, etiqueta text, detalle text, href text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_modulo = 'tareas' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.tareas_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  ELSIF p_modulo = 'obras' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.obras_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  ELSIF p_modulo = 'contactos' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.contactos_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  ELSIF p_modulo = 'presupuestos' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.presupuestos_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  END IF;
END;
$function$;
