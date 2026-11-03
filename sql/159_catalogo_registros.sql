-- Catálogo, tramo 2: permisos, categorías, colores, insumos y servicios fijos, variantes, costos y
-- servicios en %. Ficha y decisiones: decisiones/catalogo/README.md. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_registros.sql.
--
-- Categorías, colores, insumos y variantes se escriben directo, con RLS y triggers. Costos y servicios
-- en % pasan por funciones: lo cargado no se pisa, porque un presupuesto se recalcula como era, y un
-- cambio en rojo pide confirmar. Lo que depende de las versiones va después: datos que quedan fijos
-- (sql/160), bajas en cascada (sql/162) y avisos (sql/165).

-- ============================================================
-- 1. Tablas
-- ============================================================
DO $$
BEGIN
  CREATE TYPE tipo_catalogo AS ENUM ('paquete', 'insumo', 'servicio');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE unidad_insumo AS ENUM ('mm', 'm2', 'u');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE alcance_minimo AS ENUM ('paquete', 'presupuesto');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- UNIQUE (id, tipo): lo pide la FK compuesta con que la base no deja poner un insumo en una categoría
-- de paquete.
CREATE TABLE IF NOT EXISTS public.catalogo_categorias (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo       tipo_catalogo NOT NULL,
  nombre     text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, tipo)
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_categorias_nombre
  ON public.catalogo_categorias (tipo, lower(nombre)) WHERE activo;

CREATE TABLE IF NOT EXISTS public.catalogo_colores (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre     text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_colores_nombre
  ON public.catalogo_colores (lower(nombre)) WHERE activo;

CREATE TABLE IF NOT EXISTS public.catalogo_insumos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo         tipo_catalogo NOT NULL CHECK (tipo <> 'paquete'),
  nombre       text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  categoria_id uuid NOT NULL,
  unidad       unidad_insumo NOT NULL,
  peso         numeric(10,4) CHECK (peso >= 0),
  espesor      numeric(8,2) CHECK (espesor >= 0),
  con_color    boolean NOT NULL DEFAULT false,
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (categoria_id, tipo) REFERENCES public.catalogo_categorias (id, tipo),
  CONSTRAINT catalogo_insumos_servicio
    CHECK (tipo = 'insumo' OR (peso IS NULL AND espesor IS NULL AND NOT con_color))
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_insumos_nombre
  ON public.catalogo_insumos (tipo, lower(nombre)) WHERE activo;

CREATE INDEX IF NOT EXISTS catalogo_insumos_categoria
  ON public.catalogo_insumos (categoria_id);

-- color_id NULL: color indistinto. UNIQUE simple y no parcial: volver a sumar un color reactiva la
-- fila, con sus costos (decisiones/catalogo/insumos.md → El insumo).
CREATE TABLE IF NOT EXISTS public.catalogo_variantes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  insumo_id  uuid NOT NULL REFERENCES public.catalogo_insumos(id),
  color_id   uuid REFERENCES public.catalogo_colores(id),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT catalogo_variantes_una_por_color UNIQUE NULLS NOT DISTINCT (insumo_id, color_id)
);

CREATE INDEX IF NOT EXISTS catalogo_variantes_color
  ON public.catalogo_variantes (color_id);

-- created_at es desde cuándo rige: un costo rige desde que se carga, sin fecha futura.
CREATE TABLE IF NOT EXISTS public.catalogo_costos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  variante_id uuid NOT NULL REFERENCES public.catalogo_variantes(id),
  costo       numeric(14,4) NOT NULL CHECK (costo > 0),
  moneda      moneda NOT NULL,
  creado_por  uuid NOT NULL REFERENCES public.usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (variante_id, created_at)
);

-- activo copia el de_baja del último valor: la historia es la autoridad, y este activo existe para
-- que quien apunte al servicio no lea un dato falso.
CREATE TABLE IF NOT EXISTS public.catalogo_porcentajes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Cada fila es el servicio entero desde created_at. de_baja es un dato más de la historia: un
-- presupuesto de marzo cobra lo que en marzo estaba activo. Sin mínimo todo va vacío.
CREATE TABLE IF NOT EXISTS public.catalogo_porcentajes_valores (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  porcentaje_id uuid NOT NULL REFERENCES public.catalogo_porcentajes(id),
  nombre        text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  porcentaje    numeric(7,3) NOT NULL CHECK (porcentaje > 0),
  paso          integer NOT NULL CHECK (paso BETWEEN 1 AND 3),
  categorias    uuid[] NOT NULL DEFAULT '{}',
  minimo        numeric(14,4) CHECK (minimo > 0),
  minimo_moneda moneda,
  minimo_por    alcance_minimo,
  opcional      boolean NOT NULL DEFAULT false,
  de_baja       boolean NOT NULL DEFAULT false,
  revierte_id   uuid REFERENCES public.catalogo_porcentajes_valores(id),
  creado_por    uuid NOT NULL REFERENCES public.usuarios(id),
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (porcentaje_id, created_at),
  CONSTRAINT catalogo_porcentajes_valores_categorias CHECK (paso = 1 OR cardinality(categorias) = 0),
  CONSTRAINT catalogo_porcentajes_valores_minimo CHECK (num_nonnulls(minimo, minimo_moneda, minimo_por) IN (0, 3)),
  CONSTRAINT catalogo_porcentajes_valores_despeje CHECK (paso <> 3 OR minimo IS NULL)
);

CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_categorias
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_colores
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_insumos
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_variantes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_costos
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_porcentajes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_porcentajes_valores
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 2. Quién puede: una sola tabla de permisos por tipo
-- ============================================================

-- Nombre, unidad y categoría se leen desde cualquier pestaña: lo protegido es el costo
-- (decisiones/catalogo/permisos.md → Ningún permiso del catálogo requiere otro).
CREATE OR REPLACE FUNCTION public.catalogo_puede_ver()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.tiene_permiso('catalogo_paquetes') OR public.tiene_permiso('catalogo_insumos')
      OR public.tiene_permiso('catalogo_fijos') OR public.tiene_permiso('catalogo_porcentajes');
$$;

CREATE OR REPLACE FUNCTION public.catalogo_puede_editar(p_tipo tipo_catalogo)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.tiene_permiso(CASE p_tipo
    WHEN 'paquete'  THEN 'catalogo_armar'
    WHEN 'insumo'   THEN 'catalogo_cargar'
    WHEN 'servicio' THEN 'catalogo_fijos_editar'
  END);
$$;

-- Un arreglo y no un booleano por fila: en la policy se calcula una vez, no una por cada costo.
CREATE OR REPLACE FUNCTION public.catalogo_tipos_con_costo()
RETURNS tipo_catalogo[]
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN public.tiene_permiso('catalogo_costos') THEN 'insumo'::tipo_catalogo END,
    CASE WHEN public.tiene_permiso('catalogo_fijos_editar') THEN 'servicio'::tipo_catalogo END
  ], NULL);
$$;

-- ============================================================
-- 3. RLS y privilegios
-- ============================================================
ALTER TABLE public.catalogo_categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_colores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_insumos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_variantes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_costos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_porcentajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_porcentajes_valores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalogo_categorias_select ON public.catalogo_categorias;
CREATE POLICY catalogo_categorias_select ON public.catalogo_categorias
  FOR SELECT TO authenticated USING ((SELECT public.catalogo_puede_ver()));
DROP POLICY IF EXISTS catalogo_categorias_insert ON public.catalogo_categorias;
CREATE POLICY catalogo_categorias_insert ON public.catalogo_categorias
  FOR INSERT TO authenticated WITH CHECK (public.catalogo_puede_editar(tipo));
DROP POLICY IF EXISTS catalogo_categorias_update ON public.catalogo_categorias;
CREATE POLICY catalogo_categorias_update ON public.catalogo_categorias
  FOR UPDATE TO authenticated
  USING (public.catalogo_puede_editar(tipo)) WITH CHECK (public.catalogo_puede_editar(tipo));

DROP POLICY IF EXISTS catalogo_colores_select ON public.catalogo_colores;
CREATE POLICY catalogo_colores_select ON public.catalogo_colores
  FOR SELECT TO authenticated USING ((SELECT public.catalogo_puede_ver()));
DROP POLICY IF EXISTS catalogo_colores_insert ON public.catalogo_colores;
CREATE POLICY catalogo_colores_insert ON public.catalogo_colores
  FOR INSERT TO authenticated WITH CHECK ((SELECT public.tiene_permiso('catalogo_cargar')));
DROP POLICY IF EXISTS catalogo_colores_update ON public.catalogo_colores;
CREATE POLICY catalogo_colores_update ON public.catalogo_colores
  FOR UPDATE TO authenticated
  USING ((SELECT public.tiene_permiso('catalogo_cargar')))
  WITH CHECK ((SELECT public.tiene_permiso('catalogo_cargar')));

DROP POLICY IF EXISTS catalogo_insumos_select ON public.catalogo_insumos;
CREATE POLICY catalogo_insumos_select ON public.catalogo_insumos
  FOR SELECT TO authenticated USING ((SELECT public.catalogo_puede_ver()));
DROP POLICY IF EXISTS catalogo_insumos_insert ON public.catalogo_insumos;
CREATE POLICY catalogo_insumos_insert ON public.catalogo_insumos
  FOR INSERT TO authenticated WITH CHECK (public.catalogo_puede_editar(tipo));
DROP POLICY IF EXISTS catalogo_insumos_update ON public.catalogo_insumos;
CREATE POLICY catalogo_insumos_update ON public.catalogo_insumos
  FOR UPDATE TO authenticated
  USING (public.catalogo_puede_editar(tipo)) WITH CHECK (public.catalogo_puede_editar(tipo));

DROP POLICY IF EXISTS catalogo_variantes_select ON public.catalogo_variantes;
CREATE POLICY catalogo_variantes_select ON public.catalogo_variantes
  FOR SELECT TO authenticated USING ((SELECT public.catalogo_puede_ver()));
DROP POLICY IF EXISTS catalogo_variantes_insert ON public.catalogo_variantes;
CREATE POLICY catalogo_variantes_insert ON public.catalogo_variantes
  FOR INSERT TO authenticated WITH CHECK (EXISTS (
    SELECT 1 FROM public.catalogo_insumos i
    WHERE i.id = insumo_id AND public.catalogo_puede_editar(i.tipo)));
DROP POLICY IF EXISTS catalogo_variantes_update ON public.catalogo_variantes;
CREATE POLICY catalogo_variantes_update ON public.catalogo_variantes
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.catalogo_insumos i
    WHERE i.id = insumo_id AND public.catalogo_puede_editar(i.tipo)))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.catalogo_insumos i
    WHERE i.id = insumo_id AND public.catalogo_puede_editar(i.tipo)));

DROP POLICY IF EXISTS catalogo_costos_select ON public.catalogo_costos;
CREATE POLICY catalogo_costos_select ON public.catalogo_costos
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM public.catalogo_variantes va
    JOIN public.catalogo_insumos i ON i.id = va.insumo_id
    WHERE va.id = variante_id AND i.tipo = ANY ((SELECT public.catalogo_tipos_con_costo())::tipo_catalogo[])));

DROP POLICY IF EXISTS catalogo_porcentajes_select ON public.catalogo_porcentajes;
CREATE POLICY catalogo_porcentajes_select ON public.catalogo_porcentajes
  FOR SELECT TO authenticated USING ((SELECT public.tiene_permiso('catalogo_porcentajes')));
DROP POLICY IF EXISTS catalogo_porcentajes_valores_select ON public.catalogo_porcentajes_valores;
CREATE POLICY catalogo_porcentajes_valores_select ON public.catalogo_porcentajes_valores
  FOR SELECT TO authenticated USING ((SELECT public.tiene_permiso('catalogo_porcentajes')));

-- UPDATE por columna: tipo, insumo_id y color_id no se cambian nunca.
GRANT SELECT ON public.catalogo_categorias, public.catalogo_colores, public.catalogo_insumos,
  public.catalogo_variantes, public.catalogo_costos, public.catalogo_porcentajes,
  public.catalogo_porcentajes_valores TO authenticated;
GRANT INSERT ON public.catalogo_categorias, public.catalogo_colores, public.catalogo_insumos,
  public.catalogo_variantes TO authenticated;
GRANT UPDATE (nombre, activo) ON public.catalogo_categorias, public.catalogo_colores TO authenticated;
GRANT UPDATE (nombre, categoria_id, unidad, peso, espesor, con_color, activo) ON public.catalogo_insumos TO authenticated;
GRANT UPDATE (activo) ON public.catalogo_variantes TO authenticated;

-- ============================================================
-- 4. Reglas de categorías, colores, insumos y variantes
-- ============================================================

-- Una categoría de paquete no tiene insumos: lo suyo son las versiones y lo suma sql/160.
CREATE OR REPLACE FUNCTION public.catalogo_categorias_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.nombre <> OLD.nombre AND EXISTS (
    SELECT 1 FROM public.catalogo_insumos i WHERE i.categoria_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'La categoría % ya tiene algo adentro: su nombre queda fijo', OLD.nombre
      USING ERRCODE = 'CA006';
  END IF;
  IF OLD.activo AND NOT NEW.activo AND EXISTS (
    SELECT 1 FROM public.catalogo_insumos i WHERE i.categoria_id = NEW.id AND i.activo
  ) THEN
    RAISE EXCEPTION 'La categoría % tiene registros activos adentro: no se puede dar de baja', OLD.nombre
      USING ERRCODE = 'CA007';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_categorias_validar BEFORE UPDATE ON public.catalogo_categorias
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_categorias_validar();

CREATE OR REPLACE FUNCTION public.catalogo_colores_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.nombre <> OLD.nombre AND EXISTS (
    SELECT 1 FROM public.catalogo_variantes v WHERE v.color_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'El color % ya se usa: su nombre queda fijo', OLD.nombre USING ERRCODE = 'CA006';
  END IF;
  IF OLD.activo AND NOT NEW.activo AND EXISTS (
    SELECT 1 FROM public.catalogo_variantes v WHERE v.color_id = NEW.id AND v.activo
  ) THEN
    RAISE EXCEPTION 'El color % tiene variantes activas: no se puede dar de baja', OLD.nombre
      USING ERRCODE = 'CA007';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_colores_validar BEFORE UPDATE ON public.catalogo_colores
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_colores_validar();

CREATE OR REPLACE FUNCTION public.catalogo_insumos_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_categoria text;
BEGIN
  IF NEW.activo AND (TG_OP = 'INSERT' OR NOT OLD.activo OR NEW.categoria_id <> OLD.categoria_id) THEN
    SELECT c.nombre INTO v_categoria FROM public.catalogo_categorias c
    WHERE c.id = NEW.categoria_id AND NOT c.activo;
    IF FOUND THEN
      RAISE EXCEPTION 'La categoría % está de baja: reactivala primero', v_categoria USING ERRCODE = 'CA008';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_insumos_validar BEFORE INSERT OR UPDATE ON public.catalogo_insumos
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_insumos_validar();

-- La variante indistinta es el insumo: no se baja sola, se baja el insumo.
CREATE OR REPLACE FUNCTION public.catalogo_variantes_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_con_color boolean;
  v_color text;
BEGIN
  SELECT i.con_color INTO v_con_color FROM public.catalogo_insumos i WHERE i.id = NEW.insumo_id;
  IF NEW.activo AND (NEW.color_id IS NOT NULL) <> v_con_color THEN
    RAISE EXCEPTION '%', CASE WHEN v_con_color
      THEN 'Este insumo tiene colores: no lleva una variante indistinta'
      ELSE 'Este insumo es de color indistinto: no lleva colores' END
      USING ERRCODE = 'CA009';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.activo AND NOT NEW.activo AND NEW.color_id IS NULL AND NOT v_con_color THEN
    RAISE EXCEPTION 'Un insumo de color indistinto se da de baja entero' USING ERRCODE = 'CA009';
  END IF;
  IF NEW.activo AND (TG_OP = 'INSERT' OR NOT OLD.activo) THEN
    SELECT c.nombre INTO v_color FROM public.catalogo_colores c
    WHERE c.id = NEW.color_id AND NOT c.activo;
    IF FOUND THEN
      RAISE EXCEPTION 'El color % está de baja: reactivalo primero', v_color USING ERRCODE = 'CA008';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_variantes_validar BEFORE INSERT OR UPDATE ON public.catalogo_variantes
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_variantes_validar();

-- Volver a sumar un color reactiva su fila, con sus costos.
CREATE OR REPLACE FUNCTION public.catalogo_variante_sumar(p_insumo uuid, p_color uuid)
RETURNS uuid
LANGUAGE sql
SET search_path = public
AS $$
  INSERT INTO public.catalogo_variantes (insumo_id, color_id) VALUES (p_insumo, p_color)
  ON CONFLICT (insumo_id, color_id) DO UPDATE SET activo = true
  RETURNING id;
$$;

-- Indistinto: una sola variante, sin color, que nace con el insumo. Pasar a colores apaga esa y al
-- revés apaga los colores: un insumo no tiene de los dos a la vez.
CREATE OR REPLACE FUNCTION public.catalogo_insumos_variantes()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.con_color THEN
    UPDATE public.catalogo_variantes SET activo = false
    WHERE insumo_id = NEW.id AND color_id IS NULL AND activo;
  ELSE
    UPDATE public.catalogo_variantes SET activo = false
    WHERE insumo_id = NEW.id AND color_id IS NOT NULL AND activo;
    PERFORM public.catalogo_variante_sumar(NEW.id, NULL);
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_insumos_variantes_alta AFTER INSERT ON public.catalogo_insumos
  FOR EACH ROW WHEN (NOT NEW.con_color) EXECUTE FUNCTION public.catalogo_insumos_variantes();
CREATE OR REPLACE TRIGGER catalogo_insumos_variantes_cambio AFTER UPDATE OF con_color ON public.catalogo_insumos
  FOR EACH ROW WHEN (OLD.con_color <> NEW.con_color) EXECUTE FUNCTION public.catalogo_insumos_variantes();

-- ============================================================
-- 5. Costos
-- ============================================================

-- La regla de qué costo rige a una fecha. Respeta RLS: sin el permiso, vacío.
CREATE OR REPLACE FUNCTION public.catalogo_costos_vigentes(p_en timestamptz DEFAULT now())
RETURNS SETOF public.catalogo_costos
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT DISTINCT ON (c.variante_id) c.*
  FROM public.catalogo_costos c
  WHERE c.activo AND c.created_at <= p_en
  ORDER BY c.variante_id, c.created_at DESC;
$$;

-- Lo que el formulario muestra antes de guardar. El anterior se pasa a la moneda nueva con el tipo de
-- cambio del día (decisiones/catalogo/precio.md → Moneda). Filas: [{variante_id, costo, moneda}].
CREATE OR REPLACE FUNCTION public.catalogo_costos_niveles(p_filas jsonb)
RETURNS TABLE (variante_id uuid, costo numeric, moneda moneda, anterior numeric,
               anterior_moneda moneda, nivel text)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT f.variante_id, f.costo, f.moneda, a.costo, a.moneda,
         CASE WHEN a.id IS NOT NULL THEN
           public.nivel_cambio(public.monedas_convertir(a.costo, a.moneda, f.moneda), f.costo)
         END
  FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid, costo numeric, moneda moneda)
  LEFT JOIN public.catalogo_costos_vigentes() a ON a.variante_id = f.variante_id;
$$;

-- Una fila o toda una lista: se guardan juntas o ninguna. DEFINER porque la tabla no tiene INSERT: el
-- rojo sin confirmar no se saltea escribiendo directo.
CREATE OR REPLACE FUNCTION public.catalogo_costos_cargar(p_filas jsonb, p_confirmar_rojo boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tipos tipo_catalogo[] := public.catalogo_tipos_con_costo();
  v_rojas int;
  v_cargadas int;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid)
    LEFT JOIN public.catalogo_variantes va ON va.id = f.variante_id
    LEFT JOIN public.catalogo_insumos i ON i.id = va.insumo_id
    WHERE i.id IS NULL OR NOT i.tipo = ANY (v_tipos)
  ) THEN
    RAISE EXCEPTION 'Cargar este costo requiere catalogo_costos o catalogo_fijos_editar' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_rojas FROM public.catalogo_costos_niveles(p_filas) n WHERE n.nivel = 'rojo';
  IF v_rojas > 0 AND NOT coalesce(p_confirmar_rojo, false) THEN
    RAISE EXCEPTION '% 50 %% o más: confirmalo',
      CASE WHEN v_rojas = 1 THEN '1 fila cambia' ELSE v_rojas || ' filas cambian' END
      USING ERRCODE = 'CA003';
  END IF;

  INSERT INTO public.catalogo_costos (variante_id, costo, moneda, creado_por)
  SELECT f.variante_id, f.costo, f.moneda, auth.uid()
  FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid, costo numeric, moneda moneda);
  GET DIAGNOSTICS v_cargadas = ROW_COUNT;
  RETURN v_cargadas;
END;
$$;

-- ============================================================
-- 6. Altas: el insumo con sus colores, el servicio fijo con su costo
-- ============================================================

-- Sin colores: color indistinto.
CREATE OR REPLACE FUNCTION public.catalogo_insumo_alta(
  p_nombre text, p_categoria uuid, p_unidad unidad_insumo, p_peso numeric, p_espesor numeric,
  p_colores uuid[] DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.catalogo_insumos (tipo, nombre, categoria_id, unidad, peso, espesor, con_color)
  VALUES ('insumo', p_nombre, p_categoria, p_unidad, p_peso, p_espesor, coalesce(cardinality(p_colores), 0) > 0)
  RETURNING id INTO v_id;
  PERFORM public.catalogo_variante_sumar(v_id, c) FROM unnest(p_colores) AS c;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_fijo_alta(
  p_nombre text, p_categoria uuid, p_unidad unidad_insumo, p_costo numeric, p_moneda moneda
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.catalogo_insumos (tipo, nombre, categoria_id, unidad)
  VALUES ('servicio', p_nombre, p_categoria, p_unidad)
  RETURNING id INTO v_id;
  PERFORM public.catalogo_costos_cargar(jsonb_build_array(jsonb_build_object(
    'variante_id', (SELECT va.id FROM public.catalogo_variantes va WHERE va.insumo_id = v_id),
    'costo', p_costo,
    'moneda', p_moneda)));
  RETURN v_id;
END;
$$;

-- ============================================================
-- 7. Servicios en %: cada cambio es un valor nuevo con fecha
-- ============================================================

-- El último valor de cada servicio a una fecha, de baja incluidos. Respeta RLS: sin la vista, vacío.
CREATE OR REPLACE FUNCTION public.catalogo_porcentajes_vigentes(p_en timestamptz DEFAULT now())
RETURNS SETOF public.catalogo_porcentajes_valores
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT DISTINCT ON (v.porcentaje_id) v.*
  FROM public.catalogo_porcentajes_valores v
  WHERE v.activo AND v.created_at <= p_en
  ORDER BY v.porcentaje_id, v.created_at DESC;
$$;

-- El lock serializa los cambios: la suma del paso 3 y el nombre miran a los demás servicios.
CREATE OR REPLACE FUNCTION public.catalogo_porcentaje_empezar()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.tiene_permiso('catalogo_porcentajes_editar') THEN
    RAISE EXCEPTION 'Cambiar un servicio en %% requiere catalogo_porcentajes_editar' USING ERRCODE = '42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('catalogo_porcentajes'));
END;
$$;

-- El único camino a la historia: alta, cambio, baja y reversión pasan por los mismos controles. Si no
-- cambia nada, no suma fila.
CREATE OR REPLACE FUNCTION public.catalogo_porcentaje_registrar(
  p_v public.catalogo_porcentajes_valores, p_confirmar_rojo boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_a public.catalogo_porcentajes_valores;
  v_id uuid;
BEGIN
  p_v.categorias := ARRAY(SELECT DISTINCT c FROM unnest(p_v.categorias) AS c ORDER BY c);

  SELECT * INTO v_a FROM public.catalogo_porcentajes_vigentes() x WHERE x.porcentaje_id = p_v.porcentaje_id;
  IF v_a.id IS NOT NULL
     AND (v_a.nombre, v_a.porcentaje, v_a.paso, v_a.categorias, v_a.minimo, v_a.minimo_moneda,
          v_a.minimo_por, v_a.opcional, v_a.de_baja)
     IS NOT DISTINCT FROM
         (p_v.nombre, p_v.porcentaje, p_v.paso, p_v.categorias, p_v.minimo, p_v.minimo_moneda,
          p_v.minimo_por, p_v.opcional, p_v.de_baja) THEN
    RETURN v_a.id;
  END IF;

  IF public.nivel_cambio(v_a.porcentaje, p_v.porcentaje) = 'rojo' AND NOT coalesce(p_confirmar_rojo, false) THEN
    RAISE EXCEPTION 'El %% cambia 50 %% o más contra el anterior: confirmalo' USING ERRCODE = 'CA003';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(p_v.categorias) AS c
    LEFT JOIN public.catalogo_categorias x ON x.id = c AND x.tipo <> 'paquete'
    WHERE x.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Un servicio en %% se cobra sobre categorías de insumo o de servicio' USING ERRCODE = 'CA011';
  END IF;

  IF NOT p_v.de_baja THEN
    IF EXISTS (
      SELECT 1 FROM public.catalogo_porcentajes_vigentes() o
      WHERE NOT o.de_baja AND o.porcentaje_id <> p_v.porcentaje_id AND lower(o.nombre) = lower(p_v.nombre)
    ) THEN
      RAISE EXCEPTION 'Ya hay un servicio en %% activo que se llama %', p_v.nombre USING ERRCODE = 'CA010';
    END IF;
    IF p_v.paso = 3 AND p_v.porcentaje + coalesce((
      SELECT sum(o.porcentaje) FROM public.catalogo_porcentajes_vigentes() o
      WHERE NOT o.de_baja AND o.paso = 3 AND o.porcentaje_id <> p_v.porcentaje_id
    ), 0) >= 100 THEN
      RAISE EXCEPTION 'Los servicios sobre el precio final tienen que sumar menos de 100 %%' USING ERRCODE = 'CA004';
    END IF;
  END IF;

  INSERT INTO public.catalogo_porcentajes_valores
    (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda, minimo_por, opcional,
     de_baja, revierte_id, creado_por)
  VALUES
    (p_v.porcentaje_id, p_v.nombre, p_v.porcentaje, p_v.paso, p_v.categorias, p_v.minimo, p_v.minimo_moneda,
     p_v.minimo_por, p_v.opcional, p_v.de_baja, p_v.revierte_id, auth.uid())
  RETURNING id INTO v_id;

  UPDATE public.catalogo_porcentajes SET activo = NOT p_v.de_baja
  WHERE id = p_v.porcentaje_id AND activo = p_v.de_baja;
  RETURN v_id;
END;
$$;

-- p_id NULL: alta. Cambiar uno de baja lo deja de baja.
CREATE OR REPLACE FUNCTION public.catalogo_porcentaje_guardar(
  p_id uuid, p_nombre text, p_porcentaje numeric, p_paso integer, p_categorias uuid[],
  p_minimo numeric, p_minimo_moneda moneda, p_minimo_por alcance_minimo, p_opcional boolean,
  p_confirmar_rojo boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.catalogo_porcentajes_valores;
BEGIN
  PERFORM public.catalogo_porcentaje_empezar();
  IF p_id IS NULL THEN
    INSERT INTO public.catalogo_porcentajes DEFAULT VALUES RETURNING id INTO p_id;
  ELSE
    SELECT * INTO v FROM public.catalogo_porcentajes_vigentes() x WHERE x.porcentaje_id = p_id;
  END IF;
  v.porcentaje_id := p_id;
  v.nombre := p_nombre;
  v.porcentaje := p_porcentaje;
  v.paso := p_paso;
  v.categorias := coalesce(p_categorias, '{}');
  v.minimo := p_minimo;
  v.minimo_moneda := p_minimo_moneda;
  v.minimo_por := p_minimo_por;
  v.opcional := coalesce(p_opcional, false);
  v.de_baja := coalesce(v.de_baja, false);
  v.revierte_id := NULL;
  PERFORM public.catalogo_porcentaje_registrar(v, p_confirmar_rojo);
  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_porcentaje_activar(p_id uuid, p_activo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.catalogo_porcentajes_valores;
BEGIN
  PERFORM public.catalogo_porcentaje_empezar();
  SELECT * INTO v FROM public.catalogo_porcentajes_vigentes() x WHERE x.porcentaje_id = p_id;
  v.de_baja := NOT p_activo;
  v.revierte_id := NULL;
  PERFORM public.catalogo_porcentaje_registrar(v);
END;
$$;

-- Solo el último cambio. Antes del alta el servicio no se cobraba: revertirla lo deja de baja.
CREATE OR REPLACE FUNCTION public.catalogo_porcentaje_revertir(p_valor_id uuid, p_confirmar_rojo boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ultimo public.catalogo_porcentajes_valores;
  v_anterior public.catalogo_porcentajes_valores;
BEGIN
  PERFORM public.catalogo_porcentaje_empezar();
  SELECT x.* INTO v_ultimo
  FROM public.catalogo_porcentajes_valores y
  JOIN public.catalogo_porcentajes_vigentes() x ON x.porcentaje_id = y.porcentaje_id
  WHERE y.id = p_valor_id;
  IF v_ultimo.id IS DISTINCT FROM p_valor_id THEN
    RAISE EXCEPTION 'Hubo otro cambio después: revertí primero el último' USING ERRCODE = 'CA005';
  END IF;

  SELECT * INTO v_anterior FROM public.catalogo_porcentajes_valores x
  WHERE x.porcentaje_id = v_ultimo.porcentaje_id AND x.activo AND x.created_at < v_ultimo.created_at
  ORDER BY x.created_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    v_anterior := v_ultimo;
    v_anterior.de_baja := true;
  END IF;
  v_anterior.revierte_id := p_valor_id;
  RETURN public.catalogo_porcentaje_registrar(v_anterior, p_confirmar_rojo);
END;
$$;

-- DEFINER por el nombre de quien cargó. El nivel se mide contra el valor anterior.
CREATE OR REPLACE FUNCTION public.catalogo_porcentajes_historia(p_id uuid)
RETURNS TABLE (id uuid, nombre text, porcentaje numeric, paso integer, categorias uuid[], minimo numeric,
               minimo_moneda moneda, minimo_por alcance_minimo, opcional boolean, de_baja boolean,
               revierte_id uuid, cargado_por text, nivel text, ultimo boolean, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT v.id, v.nombre, v.porcentaje, v.paso, v.categorias, v.minimo, v.minimo_moneda, v.minimo_por,
         v.opcional, v.de_baja, v.revierte_id, u.nombre,
         public.nivel_cambio(lag(v.porcentaje) OVER (ORDER BY v.created_at), v.porcentaje),
         row_number() OVER (ORDER BY v.created_at DESC) = 1,
         v.created_at
  FROM public.catalogo_porcentajes_valores v
  LEFT JOIN public.usuarios u ON u.id = v.creado_por
  WHERE v.porcentaje_id = p_id AND v.activo AND public.tiene_permiso('catalogo_porcentajes')
  ORDER BY v.created_at DESC;
$$;

-- ============================================================
-- 8. Privilegios de las funciones
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.catalogo_puede_ver(),
  public.catalogo_puede_editar(tipo_catalogo),
  public.catalogo_tipos_con_costo(),
  public.catalogo_categorias_validar(),
  public.catalogo_colores_validar(),
  public.catalogo_insumos_validar(),
  public.catalogo_variantes_validar(),
  public.catalogo_variante_sumar(uuid, uuid),
  public.catalogo_insumos_variantes(),
  public.catalogo_costos_vigentes(timestamptz),
  public.catalogo_costos_niveles(jsonb),
  public.catalogo_costos_cargar(jsonb, boolean),
  public.catalogo_insumo_alta(text, uuid, unidad_insumo, numeric, numeric, uuid[]),
  public.catalogo_fijo_alta(text, uuid, unidad_insumo, numeric, moneda),
  public.catalogo_porcentajes_vigentes(timestamptz),
  public.catalogo_porcentaje_empezar(),
  public.catalogo_porcentaje_registrar(public.catalogo_porcentajes_valores, boolean),
  public.catalogo_porcentaje_guardar(uuid, text, numeric, integer, uuid[], numeric, moneda, alcance_minimo, boolean, boolean),
  public.catalogo_porcentaje_activar(uuid, boolean),
  public.catalogo_porcentaje_revertir(uuid, boolean),
  public.catalogo_porcentajes_historia(uuid)
FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION
  public.catalogo_categorias_validar(),
  public.catalogo_colores_validar(),
  public.catalogo_insumos_validar(),
  public.catalogo_variantes_validar(),
  public.catalogo_insumos_variantes(),
  public.catalogo_porcentaje_empezar(),
  public.catalogo_porcentaje_registrar(public.catalogo_porcentajes_valores, boolean)
FROM authenticated;

GRANT EXECUTE ON FUNCTION
  public.catalogo_puede_ver(),
  public.catalogo_puede_editar(tipo_catalogo),
  public.catalogo_tipos_con_costo(),
  public.catalogo_variante_sumar(uuid, uuid),
  public.catalogo_costos_vigentes(timestamptz),
  public.catalogo_costos_niveles(jsonb),
  public.catalogo_costos_cargar(jsonb, boolean),
  public.catalogo_insumo_alta(text, uuid, unidad_insumo, numeric, numeric, uuid[]),
  public.catalogo_fijo_alta(text, uuid, unidad_insumo, numeric, moneda),
  public.catalogo_porcentajes_vigentes(timestamptz),
  public.catalogo_porcentaje_guardar(uuid, text, numeric, integer, uuid[], numeric, moneda, alcance_minimo, boolean, boolean),
  public.catalogo_porcentaje_activar(uuid, boolean),
  public.catalogo_porcentaje_revertir(uuid, boolean),
  public.catalogo_porcentajes_historia(uuid)
TO authenticated;

-- ============================================================
-- 9. Catálogo de permisos (decisiones/catalogo/README.md → Ficha: todo delegable menos aprobar)
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT v.codigo, 'catalogo', 'vista', v.nombre, v.orden, true
FROM (VALUES ('catalogo_paquetes', 'Paquetes', 1),
             ('catalogo_insumos', 'Insumos', 2),
             ('catalogo_fijos', 'Servicios fijos', 3),
             ('catalogo_porcentajes', 'Servicios en %', 4)) AS v(codigo, nombre, orden)
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = v.codigo AND s.activo);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT f.codigo, 'catalogo', 'funcion', f.nombre, f.orden, v.id, f.delegable
FROM (VALUES ('catalogo_armar', 'Armar paquetes', 1, 'catalogo_paquetes', true),
             ('catalogo_aprobar', 'Aprobar versiones', 2, 'catalogo_paquetes', false),
             ('catalogo_cargar', 'Cargar insumos', 1, 'catalogo_insumos', true),
             ('catalogo_costos', 'Costos', 2, 'catalogo_insumos', true),
             ('catalogo_fijos_editar', 'Editar servicios fijos', 1, 'catalogo_fijos', true),
             ('catalogo_porcentajes_editar', 'Editar servicios en %', 1, 'catalogo_porcentajes', true)
     ) AS f(codigo, nombre, orden, vista, delegable)
JOIN public.submodulos v ON v.codigo = f.vista AND v.activo
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = f.codigo AND s.activo);
