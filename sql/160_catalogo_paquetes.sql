-- Catálogo, tramo 3: paquetes, versiones y su contenido, edición solo en borrador, versión nueva,
-- duplicar, datos del insumo que quedan fijos y la categoría de paquete con versiones adentro.
-- Ficha y decisiones: decisiones/catalogo/README.md. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_paquetes.sql.
--
-- El contenido de un borrador se escribe directo, con RLS y triggers. El estado de una versión no lo
-- escribe nadie: lo cambian las funciones del ciclo (sql/162), igual que lo que frena el envío. Mientras
-- tanto un borrador puede estar a medias: acá solo se frena lo que no tiene sentido en ningún momento.

-- ============================================================
-- 1. Tablas
-- ============================================================
DO $$
BEGIN
  CREATE TYPE estado_version_catalogo AS ENUM ('borrador', 'en_revision', 'publicado', 'obsoleto', 'descartado');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE tipo_material AS ENUM ('unico', 'elige_vendedor', 'elige_sistema', 'sigue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.catalogo_paquetes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- enviada: la lista de estados que fijan datos de insumos y categorías, en un solo lugar. Un borrador o
-- una descartada no cuentan (decisiones/catalogo/insumos.md → El insumo). categoria_tipo es la mitad de
-- la FK compuesta con que una versión no entra en una categoría de insumo.
CREATE TABLE IF NOT EXISTS public.catalogo_versiones (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paquete_id     uuid NOT NULL REFERENCES public.catalogo_paquetes(id),
  numero         integer NOT NULL,
  estado         estado_version_catalogo NOT NULL DEFAULT 'borrador',
  enviada        boolean GENERATED ALWAYS AS (estado IN ('en_revision', 'publicado', 'obsoleto')) STORED,
  nombre         text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  categoria_id   uuid NOT NULL,
  categoria_tipo tipo_catalogo GENERATED ALWAYS AS ('paquete'::tipo_catalogo) STORED,
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (paquete_id, numero),
  FOREIGN KEY (categoria_id, categoria_tipo) REFERENCES public.catalogo_categorias (id, tipo)
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_versiones_una_abierta
  ON public.catalogo_versiones (paquete_id) WHERE estado IN ('borrador', 'en_revision');
CREATE UNIQUE INDEX IF NOT EXISTS catalogo_versiones_una_publicada
  ON public.catalogo_versiones (paquete_id) WHERE estado = 'publicado';
CREATE UNIQUE INDEX IF NOT EXISTS catalogo_versiones_nombre_publicado
  ON public.catalogo_versiones (lower(nombre)) WHERE estado = 'publicado';
CREATE INDEX IF NOT EXISTS catalogo_versiones_categoria
  ON public.catalogo_versiones (categoria_id);

CREATE TABLE IF NOT EXISTS public.catalogo_versiones_colores (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  color_id   uuid NOT NULL REFERENCES public.catalogo_colores(id),
  base       boolean NOT NULL DEFAULT false,
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_versiones_colores_uno
  ON public.catalogo_versiones_colores (version_id, color_id) WHERE activo;
CREATE UNIQUE INDEX IF NOT EXISTS catalogo_versiones_colores_base
  ON public.catalogo_versiones_colores (version_id) WHERE base AND activo;
CREATE INDEX IF NOT EXISTS catalogo_versiones_colores_color
  ON public.catalogo_versiones_colores (color_id);

-- El version_id de cada tabla de contenido alimenta las FK compuestas: lo que se apunta adentro de una
-- versión no puede ser de otra.
CREATE TABLE IF NOT EXISTS public.catalogo_piezas (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id           uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  nombre               text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  orden                integer NOT NULL DEFAULT 0,
  cantidad             text NOT NULL DEFAULT '1',
  cantidad_arbol       jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(cantidad)) STORED,
  opcional             boolean NOT NULL DEFAULT false,
  incluida             boolean NOT NULL DEFAULT false,
  requiere_pieza_id    uuid,
  secundario           boolean NOT NULL DEFAULT false,
  calcula_espesor      boolean NOT NULL DEFAULT false,
  peso_a_produccion    boolean NOT NULL DEFAULT true,
  espesor_a_produccion boolean NOT NULL DEFAULT true,
  activo               boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, version_id),
  FOREIGN KEY (requiere_pieza_id, version_id) REFERENCES public.catalogo_piezas (id, version_id),
  CONSTRAINT catalogo_piezas_fija CHECK (opcional OR (NOT incluida AND NOT secundario AND requiere_pieza_id IS NULL)),
  CONSTRAINT catalogo_piezas_requiere CHECK (requiere_pieza_id <> id)
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_piezas_nombre
  ON public.catalogo_piezas (version_id, lower(nombre)) WHERE activo;

-- formula: su valor si no la ingresa el vendedor, su predeterminado si la ingresa. Una lista lleva sus
-- valores acá, en orden: el presupuesto y los casos guardan el valor, que no cambia en una versión enviada.
CREATE TABLE IF NOT EXISTS public.catalogo_variables (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id           uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  pieza_id             uuid,
  nombre               text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  orden                integer NOT NULL DEFAULT 0,
  ingresa_vendedor     boolean NOT NULL DEFAULT false,
  es_lista             boolean NOT NULL DEFAULT false,
  formula              text,
  formula_arbol        jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(formula)) STORED,
  valores              text[] NOT NULL DEFAULT '{}',
  valor_predeterminado text,
  es_cantidad          boolean NOT NULL DEFAULT false,
  minimo               numeric,
  maximo               numeric,
  secundario           boolean NOT NULL DEFAULT false,
  a_produccion         boolean NOT NULL DEFAULT true,
  activo               boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, version_id),
  FOREIGN KEY (pieza_id, version_id) REFERENCES public.catalogo_piezas (id, version_id),
  CONSTRAINT catalogo_variables_calculada CHECK (ingresa_vendedor OR (
    formula IS NOT NULL AND NOT es_lista AND NOT es_cantidad AND minimo IS NULL AND maximo IS NULL AND NOT secundario)),
  CONSTRAINT catalogo_variables_lista CHECK (CASE WHEN es_lista
    THEN formula IS NULL AND NOT es_cantidad AND minimo IS NULL AND maximo IS NULL
         AND (valor_predeterminado IS NULL OR valor_predeterminado = ANY (valores))
    ELSE cardinality(valores) = 0 AND valor_predeterminado IS NULL END)
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_variables_nombre
  ON public.catalogo_variables (version_id, lower(nombre)) WHERE activo;
CREATE INDEX IF NOT EXISTS catalogo_variables_pieza
  ON public.catalogo_variables (pieza_id);

-- medida: en mm, o en u para decirle a Producción cómo cortar. ancho, alto y area: en m2. El nombre es
-- solo del múltiple: el único se llama como su insumo, que puede repetirse en la pieza.
CREATE TABLE IF NOT EXISTS public.catalogo_materiales (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id        uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  pieza_id          uuid NOT NULL,
  orden             integer NOT NULL DEFAULT 0,
  tipo              tipo_material NOT NULL DEFAULT 'unico',
  nombre            text CHECK (nombre <> '' AND nombre = btrim(nombre)),
  insumo_id         uuid REFERENCES public.catalogo_insumos(id),
  medida            text,
  medida_arbol      jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(medida)) STORED,
  ancho             text,
  ancho_arbol       jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(ancho)) STORED,
  alto              text,
  alto_arbol        jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(alto)) STORED,
  area              text,
  area_arbol        jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(area)) STORED,
  cantidad          text NOT NULL DEFAULT '1',
  cantidad_arbol    jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(cantidad)) STORED,
  eleccion          text,
  eleccion_arbol    jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(eleccion, 'eleccion')) STORED,
  sin_eleccion      boolean NOT NULL DEFAULT false,
  sigue_material_id uuid,
  secundario        boolean NOT NULL DEFAULT false,
  cuenta_peso       boolean NOT NULL DEFAULT true,
  cuenta_espesor    boolean NOT NULL DEFAULT false,
  activo            boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, version_id),
  FOREIGN KEY (pieza_id, version_id) REFERENCES public.catalogo_piezas (id, version_id),
  FOREIGN KEY (sigue_material_id, version_id) REFERENCES public.catalogo_materiales (id, version_id),
  CONSTRAINT catalogo_materiales_sigue CHECK (sigue_material_id <> id),
  CONSTRAINT catalogo_materiales_tipo CHECK (
    (nombre IS NULL) = (tipo = 'unico')
    AND (tipo = 'unico' OR insumo_id IS NULL)
    AND (tipo = 'elige_sistema' OR eleccion IS NULL)
    AND (tipo = 'sigue' OR sigue_material_id IS NULL)
    AND (tipo = 'elige_vendedor' OR (NOT sin_eleccion AND NOT secundario)))
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_materiales_nombre
  ON public.catalogo_materiales (pieza_id, lower(nombre)) WHERE activo;
CREATE INDEX IF NOT EXISTS catalogo_materiales_version
  ON public.catalogo_materiales (version_id);
CREATE INDEX IF NOT EXISTS catalogo_materiales_insumo
  ON public.catalogo_materiales (insumo_id);
CREATE INDEX IF NOT EXISTS catalogo_materiales_sigue
  ON public.catalogo_materiales (sigue_material_id);

-- Lo que no trae, lo hereda del material. En un material que sigue a otro hay una fila por cada opción de
-- aquel: sigue_opcion_id es esa opción e insumo_id su pareja, NULL si es "ninguna". Sin fila, la pareja
-- está vacía y lo frena el envío (decisiones/catalogo/paquete.md → Editor de paquete).
CREATE TABLE IF NOT EXISTS public.catalogo_opciones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id      uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  material_id     uuid NOT NULL,
  orden           integer NOT NULL DEFAULT 0,
  insumo_id       uuid REFERENCES public.catalogo_insumos(id),
  sigue_opcion_id uuid,
  predeterminada  boolean NOT NULL DEFAULT false,
  medida          text,
  medida_arbol    jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(medida)) STORED,
  ancho           text,
  ancho_arbol     jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(ancho)) STORED,
  alto            text,
  alto_arbol      jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(alto)) STORED,
  area            text,
  area_arbol      jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(area)) STORED,
  cantidad        text,
  cantidad_arbol  jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(cantidad)) STORED,
  activo          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, version_id),
  FOREIGN KEY (material_id, version_id) REFERENCES public.catalogo_materiales (id, version_id),
  FOREIGN KEY (sigue_opcion_id, version_id) REFERENCES public.catalogo_opciones (id, version_id),
  CONSTRAINT catalogo_opciones_ninguna CHECK (insumo_id IS NOT NULL OR sigue_opcion_id IS NOT NULL),
  CONSTRAINT catalogo_opciones_predeterminada CHECK (NOT predeterminada OR sigue_opcion_id IS NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_opciones_una_predeterminada
  ON public.catalogo_opciones (material_id) WHERE predeterminada AND activo;
CREATE UNIQUE INDEX IF NOT EXISTS catalogo_opciones_una_pareja
  ON public.catalogo_opciones (material_id, sigue_opcion_id) WHERE activo;
CREATE UNIQUE INDEX IF NOT EXISTS catalogo_opciones_insumo_unico
  ON public.catalogo_opciones (material_id, insumo_id) WHERE activo AND sigue_opcion_id IS NULL;
CREATE INDEX IF NOT EXISTS catalogo_opciones_version
  ON public.catalogo_opciones (version_id);
CREATE INDEX IF NOT EXISTS catalogo_opciones_insumo
  ON public.catalogo_opciones (insumo_id);
CREATE INDEX IF NOT EXISTS catalogo_opciones_sigue
  ON public.catalogo_opciones (sigue_opcion_id);

CREATE TABLE IF NOT EXISTS public.catalogo_condiciones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id      uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  variable_id     uuid,
  material_id     uuid,
  opcion_id       uuid,
  condicion       text NOT NULL,
  condicion_arbol jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(condicion, 'condicion')) STORED,
  mensaje         text NOT NULL CHECK (mensaje <> '' AND mensaje = btrim(mensaje)),
  bloquea         boolean NOT NULL DEFAULT false,
  activo          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (variable_id, version_id) REFERENCES public.catalogo_variables (id, version_id),
  FOREIGN KEY (material_id, version_id) REFERENCES public.catalogo_materiales (id, version_id),
  FOREIGN KEY (opcion_id, version_id) REFERENCES public.catalogo_opciones (id, version_id),
  CONSTRAINT catalogo_condiciones_de_quien CHECK (num_nonnulls(variable_id, material_id, opcion_id) = 1)
);

CREATE INDEX IF NOT EXISTS catalogo_condiciones_version
  ON public.catalogo_condiciones (version_id);
CREATE INDEX IF NOT EXISTS catalogo_condiciones_variable
  ON public.catalogo_condiciones (variable_id);
CREATE INDEX IF NOT EXISTS catalogo_condiciones_material
  ON public.catalogo_condiciones (material_id);
CREATE INDEX IF NOT EXISTS catalogo_condiciones_opcion
  ON public.catalogo_condiciones (opcion_id);

-- entrada: lo que cargaría un vendedor. Su forma la define el cálculo del despiece (sql/161).
CREATE TABLE IF NOT EXISTS public.catalogo_casos (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  nombre     text NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre)),
  entrada    jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(entrada) = 'object'),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_casos_nombre
  ON public.catalogo_casos (version_id, lower(nombre)) WHERE activo;

-- ============================================================
-- 2. Reglas de las versiones y su contenido
-- ============================================================

-- numero: el siguiente, contando las descartadas. Sin INSERT sobre la columna: lo pone solo acá.
CREATE OR REPLACE FUNCTION public.catalogo_versiones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT coalesce(max(v.numero), 0) + 1 INTO NEW.numero
    FROM public.catalogo_versiones v WHERE v.paquete_id = NEW.paquete_id;
  ELSIF OLD.estado <> 'borrador'
    AND (NEW.nombre, NEW.categoria_id) IS DISTINCT FROM (OLD.nombre, OLD.categoria_id) THEN
    RAISE EXCEPTION 'Esta versión ya no está en borrador: no se edita' USING ERRCODE = 'CA012';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_versiones_validar BEFORE INSERT OR UPDATE ON public.catalogo_versiones
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_versiones_validar();

-- FOR SHARE: enviar la versión (sql/162) la toma FOR UPDATE, así no entra una edición en medio. Quien no
-- tiene catalogo_armar no llega a verla: sigue de largo y lo frena RLS, con su 42501.
CREATE OR REPLACE FUNCTION public.catalogo_contenido_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_estado estado_version_catalogo;
BEGIN
  SELECT v.estado INTO v_estado FROM public.catalogo_versiones v WHERE v.id = NEW.version_id FOR SHARE;
  IF v_estado <> 'borrador' THEN
    RAISE EXCEPTION 'Esta versión ya no está en borrador: no se edita' USING ERRCODE = 'CA012';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.activo AND NOT OLD.activo THEN
    RAISE EXCEPTION 'Lo que se sacó de un borrador no vuelve: cargalo de nuevo' USING ERRCODE = 'CA015';
  END IF;
  RETURN NEW;
END;
$$;

-- Sacar algo saca lo que depende de ello. Lo que solo lo apuntaba queda sin apuntar, y si eso deja algo
-- incompleto lo frena el envío.
CREATE OR REPLACE FUNCTION public.catalogo_contenido_baja()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  CASE TG_TABLE_NAME
    WHEN 'catalogo_piezas' THEN
      UPDATE public.catalogo_variables SET activo = false WHERE pieza_id = NEW.id AND activo;
      UPDATE public.catalogo_materiales SET activo = false WHERE pieza_id = NEW.id AND activo;
      UPDATE public.catalogo_piezas SET requiere_pieza_id = NULL WHERE requiere_pieza_id = NEW.id;
    WHEN 'catalogo_variables' THEN
      UPDATE public.catalogo_condiciones SET activo = false WHERE variable_id = NEW.id AND activo;
    WHEN 'catalogo_materiales' THEN
      UPDATE public.catalogo_opciones SET activo = false WHERE material_id = NEW.id AND activo;
      UPDATE public.catalogo_condiciones SET activo = false WHERE material_id = NEW.id AND activo;
      UPDATE public.catalogo_materiales SET sigue_material_id = NULL WHERE sigue_material_id = NEW.id;
    WHEN 'catalogo_opciones' THEN
      UPDATE public.catalogo_opciones SET activo = false WHERE sigue_opcion_id = NEW.id AND activo;
      UPDATE public.catalogo_condiciones SET activo = false WHERE opcion_id = NEW.id AND activo;
  END CASE;
  RETURN NULL;
END;
$$;

-- ============================================================
-- 3. RLS, triggers y privilegios
-- ============================================================
ALTER TABLE public.catalogo_paquetes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_versiones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalogo_paquetes_select ON public.catalogo_paquetes;
CREATE POLICY catalogo_paquetes_select ON public.catalogo_paquetes
  FOR SELECT TO authenticated USING ((SELECT public.tiene_permiso('catalogo_paquetes')));
DROP POLICY IF EXISTS catalogo_paquetes_insert ON public.catalogo_paquetes;
CREATE POLICY catalogo_paquetes_insert ON public.catalogo_paquetes
  FOR INSERT TO authenticated WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')));

DROP POLICY IF EXISTS catalogo_versiones_select ON public.catalogo_versiones;
CREATE POLICY catalogo_versiones_select ON public.catalogo_versiones
  FOR SELECT TO authenticated USING ((SELECT public.tiene_permiso('catalogo_paquetes')));
DROP POLICY IF EXISTS catalogo_versiones_insert ON public.catalogo_versiones;
CREATE POLICY catalogo_versiones_insert ON public.catalogo_versiones
  FOR INSERT TO authenticated WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')));
DROP POLICY IF EXISTS catalogo_versiones_update ON public.catalogo_versiones;
CREATE POLICY catalogo_versiones_update ON public.catalogo_versiones
  FOR UPDATE TO authenticated
  USING ((SELECT public.tiene_permiso('catalogo_armar')))
  WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')));

CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_paquetes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_versiones
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalogo_versiones_colores', 'catalogo_piezas', 'catalogo_variables',
                           'catalogo_materiales', 'catalogo_opciones', 'catalogo_condiciones', 'catalogo_casos']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR SELECT TO authenticated
      USING ((SELECT public.tiene_permiso('catalogo_paquetes')))$p$, t || '_select', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_insert', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR INSERT TO authenticated
      WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')))$p$, t || '_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_update', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated
      USING ((SELECT public.tiene_permiso('catalogo_armar')))
      WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')))$p$, t || '_update', t);

    EXECUTE format($p$CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at()$p$, t);
    EXECUTE format($p$CREATE OR REPLACE TRIGGER catalogo_contenido_validar BEFORE INSERT OR UPDATE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.catalogo_contenido_validar()$p$, t);
  END LOOP;

  FOREACH t IN ARRAY ARRAY['catalogo_piezas', 'catalogo_variables', 'catalogo_materiales', 'catalogo_opciones']
  LOOP
    EXECUTE format($p$CREATE OR REPLACE TRIGGER catalogo_contenido_baja AFTER UPDATE OF activo ON public.%I
      FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
      EXECUTE FUNCTION public.catalogo_contenido_baja()$p$, t);
  END LOOP;
END $$;

-- UPDATE por columna: version_id no se cambia nunca, y estado y numero no los escribe nadie desde afuera.
-- Dar de baja un paquete llega con el ciclo (sql/162).
GRANT SELECT ON public.catalogo_paquetes, public.catalogo_versiones, public.catalogo_versiones_colores,
  public.catalogo_piezas, public.catalogo_variables, public.catalogo_materiales, public.catalogo_opciones,
  public.catalogo_condiciones, public.catalogo_casos TO authenticated;
GRANT INSERT ON public.catalogo_paquetes, public.catalogo_versiones_colores, public.catalogo_piezas,
  public.catalogo_variables, public.catalogo_materiales, public.catalogo_opciones,
  public.catalogo_condiciones, public.catalogo_casos TO authenticated;
GRANT INSERT (paquete_id, nombre, categoria_id) ON public.catalogo_versiones TO authenticated;
GRANT UPDATE (nombre, categoria_id) ON public.catalogo_versiones TO authenticated;
GRANT UPDATE (base, activo) ON public.catalogo_versiones_colores TO authenticated;
GRANT UPDATE (nombre, orden, cantidad, opcional, incluida, requiere_pieza_id, secundario, calcula_espesor,
  peso_a_produccion, espesor_a_produccion, activo) ON public.catalogo_piezas TO authenticated;
GRANT UPDATE (pieza_id, nombre, orden, ingresa_vendedor, es_lista, formula, valores, valor_predeterminado,
  es_cantidad, minimo, maximo, secundario, a_produccion, activo) ON public.catalogo_variables TO authenticated;
GRANT UPDATE (pieza_id, orden, tipo, nombre, insumo_id, medida, ancho, alto, area, cantidad, eleccion,
  sin_eleccion, sigue_material_id, secundario, cuenta_peso, cuenta_espesor, activo)
  ON public.catalogo_materiales TO authenticated;
GRANT UPDATE (orden, insumo_id, sigue_opcion_id, predeterminada, medida, ancho, alto, area, cantidad, activo)
  ON public.catalogo_opciones TO authenticated;
GRANT UPDATE (condicion, mensaje, bloquea, activo) ON public.catalogo_condiciones TO authenticated;
GRANT UPDATE (nombre, entrada, activo) ON public.catalogo_casos TO authenticated;

-- ============================================================
-- 4. Alta, versión nueva y duplicar: todas devuelven el borrador
-- ============================================================
CREATE OR REPLACE FUNCTION public.catalogo_paquete_alta(p_nombre text, p_categoria uuid)
RETURNS uuid
LANGUAGE sql
SET search_path = public
AS $$
  WITH p AS (
    INSERT INTO public.catalogo_paquetes DEFAULT VALUES RETURNING id
  )
  INSERT INTO public.catalogo_versiones (paquete_id, nombre, categoria_id)
  SELECT p.id, p_nombre, p_categoria FROM p
  RETURNING id;
$$;

-- Las fórmulas apuntan por nombre y no cambian. Lo que apunta por id pasa por un mapa viejo → nuevo. No se
-- copia lo que se sacó del borrador, y los costos son del insumo.
CREATE OR REPLACE FUNCTION public.catalogo_version_copiar(p_origen uuid, p_paquete uuid, p_nombre text)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_destino uuid;
  v_piezas jsonb;
  v_variables jsonb;
  v_materiales jsonb;
  v_opciones jsonb;
BEGIN
  INSERT INTO public.catalogo_versiones (paquete_id, nombre, categoria_id)
  SELECT p_paquete, p_nombre, o.categoria_id FROM public.catalogo_versiones o WHERE o.id = p_origen
  RETURNING id INTO v_destino;
  IF v_destino IS NULL THEN
    RAISE EXCEPTION 'No se encontró la versión de la que se copia' USING ERRCODE = 'CA014';
  END IF;

  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_piezas
  FROM public.catalogo_piezas x WHERE x.version_id = p_origen AND x.activo;
  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_variables
  FROM public.catalogo_variables x WHERE x.version_id = p_origen AND x.activo;
  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_materiales
  FROM public.catalogo_materiales x WHERE x.version_id = p_origen AND x.activo;
  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_opciones
  FROM public.catalogo_opciones x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_versiones_colores (version_id, color_id, base)
  SELECT v_destino, x.color_id, x.base
  FROM public.catalogo_versiones_colores x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_piezas (id, version_id, nombre, orden, cantidad, opcional, incluida,
    requiere_pieza_id, secundario, calcula_espesor, peso_a_produccion, espesor_a_produccion)
  SELECT (v_piezas ->> x.id::text)::uuid, v_destino, x.nombre, x.orden, x.cantidad, x.opcional, x.incluida,
    (v_piezas ->> x.requiere_pieza_id::text)::uuid, x.secundario, x.calcula_espesor, x.peso_a_produccion,
    x.espesor_a_produccion
  FROM public.catalogo_piezas x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_variables (id, version_id, pieza_id, nombre, orden, ingresa_vendedor, es_lista,
    formula, valores, valor_predeterminado, es_cantidad, minimo, maximo, secundario, a_produccion)
  SELECT (v_variables ->> x.id::text)::uuid, v_destino, (v_piezas ->> x.pieza_id::text)::uuid, x.nombre, x.orden,
    x.ingresa_vendedor, x.es_lista, x.formula, x.valores, x.valor_predeterminado, x.es_cantidad, x.minimo,
    x.maximo, x.secundario, x.a_produccion
  FROM public.catalogo_variables x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_materiales (id, version_id, pieza_id, orden, tipo, nombre, insumo_id, medida, ancho,
    alto, area, cantidad, eleccion, sin_eleccion, sigue_material_id, secundario, cuenta_peso, cuenta_espesor)
  SELECT (v_materiales ->> x.id::text)::uuid, v_destino, (v_piezas ->> x.pieza_id::text)::uuid, x.orden, x.tipo,
    x.nombre, x.insumo_id, x.medida, x.ancho, x.alto, x.area, x.cantidad, x.eleccion, x.sin_eleccion,
    (v_materiales ->> x.sigue_material_id::text)::uuid, x.secundario, x.cuenta_peso, x.cuenta_espesor
  FROM public.catalogo_materiales x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_opciones (id, version_id, material_id, orden, insumo_id, sigue_opcion_id,
    predeterminada, medida, ancho, alto, area, cantidad)
  SELECT (v_opciones ->> x.id::text)::uuid, v_destino, (v_materiales ->> x.material_id::text)::uuid, x.orden,
    x.insumo_id, (v_opciones ->> x.sigue_opcion_id::text)::uuid, x.predeterminada, x.medida, x.ancho, x.alto,
    x.area, x.cantidad
  FROM public.catalogo_opciones x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_condiciones (version_id, variable_id, material_id, opcion_id, condicion, mensaje, bloquea)
  SELECT v_destino, (v_variables ->> x.variable_id::text)::uuid, (v_materiales ->> x.material_id::text)::uuid,
    (v_opciones ->> x.opcion_id::text)::uuid, x.condicion, x.mensaje, x.bloquea
  FROM public.catalogo_condiciones x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_casos (version_id, nombre, entrada)
  SELECT v_destino, x.nombre, x.entrada
  FROM public.catalogo_casos x WHERE x.version_id = p_origen AND x.activo;

  RETURN v_destino;
END;
$$;

-- Sin origen, sale de la publicada. El índice catalogo_versiones_una_abierta ya frena otra abierta: esto
-- lo dice con un mensaje que se entiende.
CREATE OR REPLACE FUNCTION public.catalogo_version_nueva(p_paquete uuid, p_origen uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_abierta integer;
  v_origen public.catalogo_versiones;
BEGIN
  SELECT v.numero INTO v_abierta FROM public.catalogo_versiones v
  WHERE v.paquete_id = p_paquete AND v.estado IN ('borrador', 'en_revision');
  IF FOUND THEN
    RAISE EXCEPTION 'Este paquete ya tiene abierta la v%: seguí esa, o descartala', v_abierta
      USING ERRCODE = 'CA013';
  END IF;

  SELECT v.* INTO v_origen FROM public.catalogo_versiones v
  WHERE v.paquete_id = p_paquete
    AND CASE WHEN p_origen IS NULL THEN v.estado = 'publicado' ELSE v.id = p_origen END;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión de este paquete de la que se copia' USING ERRCODE = 'CA014';
  END IF;

  RETURN public.catalogo_version_copiar(v_origen.id, p_paquete, v_origen.nombre);
END;
$$;

-- Sale de cualquier versión, la que se está mirando. Sin vínculo con el original.
CREATE OR REPLACE FUNCTION public.catalogo_paquete_duplicar(p_version uuid, p_nombre text)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_paquete uuid;
BEGIN
  INSERT INTO public.catalogo_paquetes DEFAULT VALUES RETURNING id INTO v_paquete;
  RETURN public.catalogo_version_copiar(p_version, v_paquete, p_nombre);
END;
$$;

-- ============================================================
-- 5. Lo que una versión enviada deja fijo
-- ============================================================

-- SECURITY DEFINER en los dos: quien edita un insumo o un servicio puede no ver los paquetes (Administración
-- no tiene la vista), y con RLS estos controles pasarían sin encontrar nada.
CREATE OR REPLACE FUNCTION public.catalogo_categorias_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.nombre <> OLD.nombre AND (
    EXISTS (SELECT 1 FROM public.catalogo_insumos i WHERE i.categoria_id = NEW.id)
    OR EXISTS (SELECT 1 FROM public.catalogo_versiones v WHERE v.categoria_id = NEW.id AND v.enviada)
  ) THEN
    RAISE EXCEPTION 'La categoría % ya tiene algo adentro: su nombre queda fijo', OLD.nombre
      USING ERRCODE = 'CA006';
  END IF;
  IF OLD.activo AND NOT NEW.activo AND (
    EXISTS (SELECT 1 FROM public.catalogo_insumos i WHERE i.categoria_id = NEW.id AND i.activo)
    OR EXISTS (
      SELECT 1 FROM public.catalogo_versiones v
      JOIN public.catalogo_paquetes p ON p.id = v.paquete_id
      WHERE v.categoria_id = NEW.id AND v.estado = 'publicado' AND p.activo)
  ) THEN
    RAISE EXCEPTION 'La categoría % tiene registros activos adentro: no se puede dar de baja', OLD.nombre
      USING ERRCODE = 'CA007';
  END IF;
  RETURN NEW;
END;
$$;

-- Un peso o espesor vacío se completa una vez: ninguna versión que lo contara pudo enviarse sin él.
CREATE OR REPLACE FUNCTION public.catalogo_insumos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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
  IF TG_OP = 'UPDATE' AND (
       NEW.nombre <> OLD.nombre OR NEW.categoria_id <> OLD.categoria_id OR NEW.unidad <> OLD.unidad
    OR NEW.con_color <> OLD.con_color
    OR (OLD.peso IS NOT NULL AND NEW.peso IS DISTINCT FROM OLD.peso)
    OR (OLD.espesor IS NOT NULL AND NEW.espesor IS DISTINCT FROM OLD.espesor)
  ) AND EXISTS (
    SELECT 1 FROM public.catalogo_materiales m
    JOIN public.catalogo_versiones v ON v.id = m.version_id
    WHERE m.insumo_id = NEW.id AND m.activo AND v.enviada
    UNION ALL
    SELECT 1 FROM public.catalogo_opciones o
    JOIN public.catalogo_versiones v ON v.id = o.version_id
    WHERE o.insumo_id = NEW.id AND o.activo AND v.enviada
  ) THEN
    RAISE EXCEPTION '% ya está en una versión enviada: solo cambian el costo, las variantes y si está activo. Si está mal, cargá otro', OLD.nombre
      USING ERRCODE = 'CA006';
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 6. Privilegios de las funciones
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.catalogo_versiones_validar(),
  public.catalogo_contenido_validar(),
  public.catalogo_contenido_baja(),
  public.catalogo_paquete_alta(text, uuid),
  public.catalogo_version_copiar(uuid, uuid, text),
  public.catalogo_version_nueva(uuid, uuid),
  public.catalogo_paquete_duplicar(uuid, text)
FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION
  public.catalogo_versiones_validar(),
  public.catalogo_contenido_validar(),
  public.catalogo_contenido_baja()
FROM authenticated;

GRANT EXECUTE ON FUNCTION
  public.catalogo_paquete_alta(text, uuid),
  public.catalogo_version_copiar(uuid, uuid, text),
  public.catalogo_version_nueva(uuid, uuid),
  public.catalogo_paquete_duplicar(uuid, text)
TO authenticated;
