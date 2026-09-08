-- ============================================================
-- 033 — Agenda de Obras: altas y vínculos que esperan autorización
--
-- Dos pedidos del usuario, una sola mecánica:
--
--   1. Una obra, empresa o persona nueva que se parece a algo que ya existe
--      no entra a la agenda: entra congelada, y un administrador decide.
--   2. Vincular a una obra propia una persona o empresa que cargó otro
--      tampoco entra directo. Vincular es lo que abre el teléfono de esa
--      persona (`obras_ficha_persona`), así que es la puerta que faltaba
--      cerrar: hasta hoy alcanzaba con encontrarla en el buscador de
--      identidad mínima para después leerle el contacto.
--
-- "Administrador" es quien tiene `obras_aprobar`. El sistema no tiene roles
-- (CLAUDE.md), así que la autorización nueva es un submódulo más.
--
-- CONGELADA, NO MARCADA
--
-- Decisión del usuario: mientras espera, la fila existe pero no participa.
-- No la ve nadie más que quien la creó y quien aprueba, y no se le puede
-- colgar ningún vínculo. Un `pendiente` que solo pintara un badge dejaría al
-- duplicado propagándose por las obras mientras la cola espera.
--
--   pendiente = true                      → en la cola
--   pendiente = false, activo = true      → aprobada
--   pendiente = false, activo = false,
--   motivo_rechazo IS NOT NULL            → rechazada
--
-- Sin tercer estado: los dos booleanos que ya existían alcanzan.
--
-- EL VÍNCULO PENDIENTE NO DA ACCESO AL CONTACTO
--
-- `obras_puede_ver_persona` deja de contar los vínculos pendientes. Si los
-- contara, el vendedor vincularía, leería el teléfono y esperaría el rechazo
-- sentado: la autorización sería decorativa.
--
-- POR QUÉ SE REESCRIBEN LAS TRES `obras_buscar_duplicados_*`
--
-- La detección tiene que correr en la base, no depender de que el cliente
-- confiese que vio el aviso. Los triggers necesitan el mismo criterio de
-- parecido que ya usa la pantalla, pero sin el enmascarado ni el guard de
-- permiso que esas funciones aplican al resultado.
--
-- Se parte cada una en dos: `obras_similares_*` hace el match crudo (ids y
-- score, sin mirar quién pregunta) y `obras_buscar_duplicados_*` queda como
-- la capa que enmascara y verifica permiso. Un solo umbral, un solo criterio,
-- tres consumidores: la pantalla, el trigger y la cola de aprobación.
-- ============================================================

-- ============================================================
-- 1. Las dos columnas, en las cinco tablas que pueden quedar en la cola
-- ============================================================
ALTER TABLE obras              ADD COLUMN IF NOT EXISTS pendiente boolean NOT NULL DEFAULT false;
ALTER TABLE obras              ADD COLUMN IF NOT EXISTS motivo_rechazo text;
ALTER TABLE obras_empresas     ADD COLUMN IF NOT EXISTS pendiente boolean NOT NULL DEFAULT false;
ALTER TABLE obras_empresas     ADD COLUMN IF NOT EXISTS motivo_rechazo text;
ALTER TABLE obras_personas     ADD COLUMN IF NOT EXISTS pendiente boolean NOT NULL DEFAULT false;
ALTER TABLE obras_personas     ADD COLUMN IF NOT EXISTS motivo_rechazo text;
ALTER TABLE obras_obra_empresa ADD COLUMN IF NOT EXISTS pendiente boolean NOT NULL DEFAULT false;
ALTER TABLE obras_obra_empresa ADD COLUMN IF NOT EXISTS motivo_rechazo text;
ALTER TABLE obras_obra_persona ADD COLUMN IF NOT EXISTS pendiente boolean NOT NULL DEFAULT false;
ALTER TABLE obras_obra_persona ADD COLUMN IF NOT EXISTS motivo_rechazo text;

-- Índices parciales: la cola pregunta por `pendiente` y son cinco tablas que
-- van a estar casi enteras en false.
CREATE INDEX IF NOT EXISTS idx_obras_pendiente              ON obras(created_at)              WHERE pendiente;
CREATE INDEX IF NOT EXISTS idx_obras_empresas_pendiente     ON obras_empresas(created_at)     WHERE pendiente;
CREATE INDEX IF NOT EXISTS idx_obras_personas_pendiente     ON obras_personas(created_at)     WHERE pendiente;
CREATE INDEX IF NOT EXISTS idx_obras_obra_empresa_pendiente ON obras_obra_empresa(created_at) WHERE pendiente;
CREATE INDEX IF NOT EXISTS idx_obras_obra_persona_pendiente ON obras_obra_persona(created_at) WHERE pendiente;

-- ============================================================
-- 2. GRANT UPDATE por columna
--
-- `obras` ya lo tenía así desde sql/027 (`activo` y `responsable_id` afuera),
-- y las columnas nuevas quedan fuera de esa lista sin tocar nada. Las otras
-- cuatro tablas tenían UPDATE entero: con eso, un PUT por PostgREST se
-- auto-aprueba poniendo `pendiente = false`. Ocultar el botón no autoriza.
--
-- De paso salen `creado_por` y las columnas `_norm`, que nunca tuvieron por
-- qué ser escribibles desde el cliente.
-- ============================================================
REVOKE UPDATE ON public.obras_empresas FROM authenticated;
GRANT UPDATE (
  razon_social, nombre_comercial, website, telefono, email,
  direccion, localidad, provincia, observaciones, activo
) ON public.obras_empresas TO authenticated;

REVOKE UPDATE ON public.obras_personas FROM authenticated;
GRANT UPDATE (
  nombre, apellido, telefono, whatsapp, email, observaciones, activo
) ON public.obras_personas TO authenticated;

REVOKE UPDATE ON public.obras_obra_empresa FROM authenticated;
GRANT UPDATE (roles, observaciones, activo) ON public.obras_obra_empresa TO authenticated;

REVOKE UPDATE ON public.obras_obra_persona FROM authenticated;
GRANT UPDATE (roles, empresa_id, observaciones, activo) ON public.obras_obra_persona TO authenticated;

-- ============================================================
-- 3. El match crudo, extraído de las tres funciones de búsqueda
--
-- Mismo umbral 0.45 y mismos campos que antes: esto es la mitad de abajo de
-- las funciones que ya existían, no un criterio nuevo. Devuelven ids, no
-- datos — quien los convierte en filas legibles es el que los llama, y cada
-- uno enmascara según a quién le responde.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_similares_obra(
  p_nombre     text,
  p_direccion  text DEFAULT NULL,
  p_localidad  text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (obra_id uuid, score real, misma_localidad boolean)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  WITH candidatas AS (
    SELECT o.id, o.localidad_norm,
           greatest(
             extensions.similarity(o.nombre_norm, obras_normalizar(p_nombre)),
             CASE
               WHEN p_direccion IS NULL OR o.direccion_norm IS NULL THEN 0
               ELSE extensions.similarity(o.direccion_norm, obras_normalizar(p_direccion))
             END
           ) AS score
    FROM obras o
    WHERE o.activo AND o.id IS DISTINCT FROM p_excluir_id
  )
  SELECT c.id, c.score,
         (p_localidad IS NOT NULL
           AND c.localidad_norm IS NOT NULL
           AND c.localidad_norm = obras_normalizar(p_localidad))
  FROM candidatas c
  WHERE c.score >= 0.45
  ORDER BY 3 DESC, 2 DESC
  LIMIT 5;
$$;

-- La única de las tres que se le otorga a `authenticated`: el envoltorio de
-- empresas es SECURITY INVOKER (así la RLS de obras_empresas sigue siendo la
-- que decide qué ve cada uno) y por lo tanto ejecuta esto como quien llama.
CREATE OR REPLACE FUNCTION obras_similares_empresa(
  p_razon_social     text,
  p_nombre_comercial text DEFAULT NULL,
  p_excluir_id       uuid DEFAULT NULL
)
RETURNS TABLE (empresa_id uuid, score real)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  WITH candidatas AS (
    SELECT e.id,
           greatest(
             extensions.similarity(e.razon_social_norm, obras_normalizar(p_razon_social)),
             CASE
               WHEN p_nombre_comercial IS NULL OR e.nombre_comercial_norm IS NULL THEN 0
               ELSE extensions.similarity(e.nombre_comercial_norm, obras_normalizar(p_nombre_comercial))
             END
           ) AS score
    FROM obras_empresas e
    WHERE e.activo AND e.id IS DISTINCT FROM p_excluir_id
  )
  SELECT c.id, c.score
  FROM candidatas c
  WHERE c.score >= 0.45
  ORDER BY c.score DESC
  LIMIT 5;
$$;

CREATE OR REPLACE FUNCTION obras_similares_persona(
  p_nombre     text,
  p_apellido   text DEFAULT NULL,
  p_email      text DEFAULT NULL,
  p_telefono   text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (persona_id uuid, coincide text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT p.id,
         CASE
           WHEN p.email_norm IS NOT NULL
            AND p.email_norm = nullif(lower(btrim(coalesce(p_email, ''))), '') THEN 'email'
           WHEN p.telefono_norm IS NOT NULL
            AND p.telefono_norm = obras_normalizar_telefono(p_telefono) THEN 'telefono'
           ELSE 'nombre'
         END
  FROM obras_personas p
  WHERE p.activo
    AND p.id IS DISTINCT FROM p_excluir_id
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
-- 4. Las tres de siempre, ahora como capa de enmascarado
--
-- Firma idéntica: los GRANT de sql/029 y sql/031 sobreviven al REPLACE y
-- `actions.ts` no se entera. Lo que cambia es que el criterio de parecido ya
-- no vive acá.
-- ============================================================

-- Aviso ciego: de una obra ajena, el nombre del responsable y nada más.
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_obra(
  p_nombre     text,
  p_direccion  text DEFAULT NULL,
  p_localidad  text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  es_mia       boolean,
  obra_id      uuid,
  nombre       text,
  direccion    text,
  localidad    text,
  responsable  text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT o.responsable_id = auth.uid(),
         CASE WHEN o.responsable_id = auth.uid() THEN o.id END,
         CASE WHEN o.responsable_id = auth.uid() THEN o.nombre END,
         CASE WHEN o.responsable_id = auth.uid() THEN o.direccion END,
         CASE WHEN o.responsable_id = auth.uid() THEN o.localidad END,
         u.nombre
  FROM obras_similares_obra(p_nombre, p_direccion, p_localidad, p_excluir_id) s
  JOIN obras o    ON o.id = s.obra_id
  JOIN usuarios u ON u.id = o.responsable_id
  WHERE tiene_permiso('obras_ver')
  ORDER BY s.misma_localidad DESC, s.score DESC;
$$;

-- INVOKER a propósito: las empresas son compartidas y la policy ya dice
-- quién ve cuál. Ahora esa policy además esconde las pendientes ajenas, así
-- que el buscador tampoco las ofrece.
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_empresa(
  p_razon_social      text,
  p_nombre_comercial  text DEFAULT NULL,
  p_excluir_id        uuid DEFAULT NULL
)
RETURNS TABLE (
  empresa_id        uuid,
  razon_social      text,
  nombre_comercial  text,
  localidad         text
)
LANGUAGE sql SECURITY INVOKER STABLE SET search_path = public
AS $$
  SELECT e.id, e.razon_social, e.nombre_comercial, e.localidad
  FROM obras_similares_empresa(p_razon_social, p_nombre_comercial, p_excluir_id) s
  JOIN obras_empresas e ON e.id = s.empresa_id
  ORDER BY s.score DESC;
$$;

-- Identidad mínima: nombre, apellido y empresa principal. Nunca contacto.
-- La persona congelada de otro no aparece — no se puede vincular, así que
-- ofrecerla sería ofrecer un error.
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_persona(
  p_nombre     text,
  p_apellido   text DEFAULT NULL,
  p_email      text DEFAULT NULL,
  p_telefono   text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  persona_id  uuid,
  nombre      text,
  apellido    text,
  empresa     text,
  coincide    text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
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
         s.coincide
  FROM obras_similares_persona(p_nombre, p_apellido, p_email, p_telefono, p_excluir_id) s
  JOIN obras_personas p ON p.id = s.persona_id
  WHERE (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (NOT p.pendiente OR p.creado_por = auth.uid());
$$;

-- ============================================================
-- 5. Marcar pendiente — un trigger BEFORE INSERT, cinco tablas
--
-- Para las tres entidades el criterio es el parecido; para los dos vínculos,
-- de quién es lo que se está vinculando. `NEW.pendiente` se pisa siempre en
-- los vínculos y `motivo_rechazo` en las cinco: el GRANT de INSERT es por
-- tabla, así que sin esto un cliente podría mandar la fila ya aprobada.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_marcar_pendiente()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_creador uuid;
BEGIN
  NEW.motivo_rechazo := NULL;

  IF TG_TABLE_NAME = 'obras' THEN
    IF EXISTS (SELECT 1 FROM obras_similares_obra(NEW.nombre, NEW.direccion, NEW.localidad, NEW.id)) THEN
      NEW.pendiente := true;
    END IF;

  ELSIF TG_TABLE_NAME = 'obras_empresas' THEN
    IF EXISTS (SELECT 1 FROM obras_similares_empresa(NEW.razon_social, NEW.nombre_comercial, NEW.id)) THEN
      NEW.pendiente := true;
    END IF;

  ELSIF TG_TABLE_NAME = 'obras_personas' THEN
    IF EXISTS (SELECT 1 FROM obras_similares_persona(NEW.nombre, NEW.apellido, NEW.email, NEW.telefono, NEW.id)) THEN
      NEW.pendiente := true;
    END IF;

  ELSIF TG_TABLE_NAME = 'obras_obra_empresa' THEN
    SELECT creado_por INTO v_creador FROM obras_empresas WHERE id = NEW.empresa_id;
    NEW.pendiente := v_creador IS DISTINCT FROM auth.uid();

  ELSIF TG_TABLE_NAME = 'obras_obra_persona' THEN
    SELECT creado_por INTO v_creador FROM obras_personas WHERE id = NEW.persona_id;
    NEW.pendiente := v_creador IS DISTINCT FROM auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS marcar_pendiente ON obras;
CREATE TRIGGER marcar_pendiente BEFORE INSERT ON obras
  FOR EACH ROW EXECUTE FUNCTION obras_marcar_pendiente();

DROP TRIGGER IF EXISTS marcar_pendiente ON obras_empresas;
CREATE TRIGGER marcar_pendiente BEFORE INSERT ON obras_empresas
  FOR EACH ROW EXECUTE FUNCTION obras_marcar_pendiente();

DROP TRIGGER IF EXISTS marcar_pendiente ON obras_personas;
CREATE TRIGGER marcar_pendiente BEFORE INSERT ON obras_personas
  FOR EACH ROW EXECUTE FUNCTION obras_marcar_pendiente();

DROP TRIGGER IF EXISTS marcar_pendiente ON obras_obra_empresa;
CREATE TRIGGER marcar_pendiente BEFORE INSERT ON obras_obra_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_marcar_pendiente();

DROP TRIGGER IF EXISTS marcar_pendiente ON obras_obra_persona;
CREATE TRIGGER marcar_pendiente BEFORE INSERT ON obras_obra_persona
  FOR EACH ROW EXECUTE FUNCTION obras_marcar_pendiente();

-- ============================================================
-- 6. Congelada: nada se le cuelga a una fila que está en la cola
--
-- `obras_obra_persona.empresa_id` queda afuera a propósito: es contexto
-- informativo ("a quién representa acá"), no un vínculo con la empresa.
--
-- Los IF van anidados y no encadenados con AND: plpgsql planea la expresión
-- entera la primera vez que la ejecuta, así que `TG_TABLE_NAME IN (...) AND
-- EXISTS (... NEW.obra_id ...)` explota con 42703 en `obras_persona_empresa`,
-- que no tiene esa columna. El guard de tabla no corta la referencia porque no
-- hay short-circuit a nivel de plan. Anidado, el statement que la nombra solo
-- se ejecuta —y solo se planea— para la tabla correcta.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_guard_congelado()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME IN ('obras_obra_empresa', 'obras_obra_persona', 'obras_obra_referente') THEN
    IF EXISTS (SELECT 1 FROM obras WHERE id = NEW.obra_id AND pendiente) THEN
      RAISE EXCEPTION 'La obra está pendiente de autorización: no se le pueden agregar vínculos hasta que la aprueben.'
        USING ERRCODE = 'OB011';
    END IF;
  END IF;

  IF TG_TABLE_NAME IN ('obras_obra_empresa', 'obras_persona_empresa') THEN
    IF EXISTS (SELECT 1 FROM obras_empresas WHERE id = NEW.empresa_id AND pendiente) THEN
      RAISE EXCEPTION 'Esa empresa está pendiente de autorización: no se puede vincular hasta que la aprueben.'
        USING ERRCODE = 'OB012';
    END IF;
  END IF;

  IF TG_TABLE_NAME IN ('obras_obra_persona', 'obras_persona_empresa', 'obras_obra_referente') THEN
    IF EXISTS (SELECT 1 FROM obras_personas WHERE id = NEW.persona_id AND pendiente) THEN
      RAISE EXCEPTION 'Esa persona está pendiente de autorización: no se puede vincular hasta que la aprueben.'
        USING ERRCODE = 'OB012';
    END IF;
  END IF;

  -- Marcar referente no puede ser el atajo que saltea la autorización.
  -- `obras_puede_ver_persona` cuenta las filas de `obras_obra_referente` como
  -- acceso, y esa tabla no tiene `pendiente`: sin esto quedaba el camino de
  -- encontrar a alguien ajeno en el buscador de identidad mínima, marcarlo
  -- referente de una obra propia y leerle el teléfono sin pasar por nadie. La
  -- UI ya ofrecía solo gente vinculada, así que no cambia ningún flujo real.
  IF TG_TABLE_NAME = 'obras_obra_referente' THEN
    IF NOT obras_puede_ver_persona(NEW.persona_id) THEN
      RAISE EXCEPTION 'Para marcarla referente, la persona tiene que estar vinculada a la obra y con el vínculo autorizado.'
        USING ERRCODE = 'OB019';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_congelado ON obras_obra_empresa;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_obra_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

DROP TRIGGER IF EXISTS guard_congelado ON obras_obra_persona;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_obra_persona
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

DROP TRIGGER IF EXISTS guard_congelado ON obras_persona_empresa;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_persona_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

DROP TRIGGER IF EXISTS guard_congelado ON obras_obra_referente;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_obra_referente
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

-- ============================================================
-- 7. Visibilidad: la fila congelada no existe para los demás, y el vínculo
--    pendiente no abre la ficha
--
-- Lo segundo es el punto entero del pedido 2. `obras_puede_ver_persona` es la
-- función que autoriza `obras_ficha_persona()`, que es el único camino al
-- teléfono: si contara los vínculos pendientes, vincular seguiría siendo
-- suficiente para leer el contacto y la aprobación no protegería nada.
--
-- `obras_aprobar` NO entra acá. La primera versión lo tenía —para que quien
-- aprueba viera la persona congelada— y eso convertía el permiso de aprobar en
-- la agenda entera con contacto incluido, más de lo que da
-- `obras_personas_todas`. Lo cazaron los casos 06 y 07 de
-- `sql/tests/obras_033.sql`. Quien aprueba mira por `obras_pendientes()` y
-- `obras_pendiente_similares()`, que devuelven identidad mínima: la pantalla
-- que vigila el acceso al contacto no puede ser otra puerta al contacto.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_ver_persona(p_persona_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (public.tiene_permiso('obras_ver') OR public.tiene_permiso('obras_personas'))
    AND EXISTS (
      SELECT 1 FROM public.obras_personas p
      WHERE p.id = p_persona_id
        AND (
          p.creado_por = auth.uid()
          OR (
            NOT p.pendiente
            AND (
              public.tiene_permiso('obras_personas_todas')
              OR EXISTS (
                SELECT 1 FROM public.obras_obra_persona op
                JOIN public.obras o ON o.id = op.obra_id
                WHERE op.persona_id = p_persona_id AND op.activo AND NOT op.pendiente
                  AND o.responsable_id = auth.uid()
              )
              OR EXISTS (
                SELECT 1 FROM public.obras_obra_referente r
                JOIN public.obras o ON o.id = r.obra_id
                WHERE r.persona_id = p_persona_id AND r.activo
                  AND o.responsable_id = auth.uid()
              )
            )
          )
        )
    );
$$;

-- Empresas: compartidas menos las congeladas, que son de quien las cargó
-- hasta que se resuelvan.
DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas FOR SELECT
  USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
    AND (NOT pendiente OR creado_por = auth.uid() OR tiene_permiso('obras_aprobar'))
  );

-- ============================================================
-- 8. El log de decisiones
--
-- Sin `activo` y sin FK a la fila decidida: es un log de cinco tablas y el
-- `tipo` dice cuál. Vale lo mismo que `obras_transferencias` — "¿por qué me
-- rechazaron esto?" necesita respuesta, y `motivo_rechazo` sola no dice quién
-- ni cuándo.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_aprobaciones (
  id            uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tipo          text NOT NULL CHECK (tipo IN ('obra','empresa','persona','obra_empresa','obra_persona')),
  registro_id   uuid NOT NULL,
  etiqueta      text NOT NULL,
  aprobada      boolean NOT NULL,
  motivo        text,
  decidido_por  uuid NOT NULL REFERENCES usuarios(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_obras_aprobaciones_fecha ON obras_aprobaciones(created_at DESC);

ALTER TABLE obras_aprobaciones ENABLE ROW LEVEL SECURITY;

-- Se lee desde la vista de Pendientes; lo escribe la función que decide.
DROP POLICY IF EXISTS obras_aprobaciones_select ON obras_aprobaciones;
CREATE POLICY obras_aprobaciones_select ON obras_aprobaciones FOR SELECT
  USING (tiene_permiso('obras_pendientes'));

GRANT SELECT ON public.obras_aprobaciones TO authenticated;

-- ============================================================
-- 9. Etiquetas — un solo lugar donde una fila de cualquiera de las cinco
--    tablas se convierte en texto
-- ============================================================
CREATE OR REPLACE FUNCTION obras_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN (SELECT o.nombre FROM obras o WHERE o.id = p_id)
    WHEN 'empresa' THEN (SELECT e.razon_social FROM obras_empresas e WHERE e.id = p_id)
    WHEN 'persona' THEN (
      SELECT btrim(p.nombre || ' ' || coalesce(p.apellido, ''))
      FROM obras_personas p WHERE p.id = p_id
    )
    WHEN 'obra_empresa' THEN (
      SELECT e.razon_social || ' → ' || o.nombre
      FROM obras_obra_empresa oe
      JOIN obras_empresas e ON e.id = oe.empresa_id
      JOIN obras o          ON o.id = oe.obra_id
      WHERE oe.id = p_id
    )
    WHEN 'obra_persona' THEN (
      SELECT btrim(p.nombre || ' ' || coalesce(p.apellido, '')) || ' → ' || o.nombre
      FROM obras_obra_persona op
      JOIN obras_personas p ON p.id = op.persona_id
      JOIN obras o          ON o.id = op.obra_id
      WHERE op.id = p_id
    )
  END;
$$;

-- ============================================================
-- 10. La cola
--
-- SECURITY DEFINER con guard propio, igual que las de auditoría: quien
-- aprueba necesita ver las cinco tablas enteras, y no tiene por qué tener
-- permiso sobre la agenda ni sobre las obras ajenas.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_pendientes()
RETURNS TABLE (
  tipo        text,
  registro_id uuid,
  etiqueta    text,
  motivo      text,
  solicitante text,
  created_at  timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_pendientes') THEN
    RAISE EXCEPTION 'Sin permiso para ver las autorizaciones pendientes' USING ERRCODE = 'OB013';
  END IF;

  RETURN QUERY
  WITH filas AS (
    SELECT 'obra'::text AS tipo, o.id, o.created_at, o.responsable_id AS solicitante,
           'Posible duplicado de una obra que ya existe'::text AS motivo
    FROM obras o WHERE o.pendiente AND o.activo
    UNION ALL
    SELECT 'empresa', e.id, e.created_at, e.creado_por,
           'Posible duplicado de una empresa que ya existe'
    FROM obras_empresas e WHERE e.pendiente AND e.activo
    UNION ALL
    SELECT 'persona', p.id, p.created_at, p.creado_por,
           'Posible duplicado de una persona que ya existe'
    FROM obras_personas p WHERE p.pendiente AND p.activo
    UNION ALL
    SELECT 'obra_empresa', oe.id, oe.created_at, o.responsable_id,
           'Empresa cargada por otro usuario'
    FROM obras_obra_empresa oe
    JOIN obras o ON o.id = oe.obra_id
    WHERE oe.pendiente AND oe.activo
    UNION ALL
    SELECT 'obra_persona', op.id, op.created_at, o.responsable_id,
           'Persona cargada por otro usuario'
    FROM obras_obra_persona op
    JOIN obras o ON o.id = op.obra_id
    WHERE op.pendiente AND op.activo
  )
  SELECT f.tipo, f.id, obras_etiqueta(f.tipo, f.id), f.motivo, u.nombre, f.created_at
  FROM filas f
  JOIN usuarios u ON u.id = f.solicitante
  ORDER BY f.created_at
  LIMIT 500;
END;
$$;

-- ============================================================
-- 11. Contra qué se parece
--
-- Excepción consciente al aviso ciego: acá el nombre de la obra ajena sí se
-- muestra. Sin ver contra qué se parece, la decisión de aprobar es a ciegas,
-- que es lo contrario de lo que la cola existe para hacer. Queda acotada a
-- `obras_aprobar` y no devuelve contacto de nadie.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_pendiente_similares(p_tipo text, p_id uuid)
RETURNS TABLE (etiqueta text, detalle text)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_aprobar') THEN
    RAISE EXCEPTION 'Sin permiso para resolver autorizaciones' USING ERRCODE = 'OB014';
  END IF;

  IF p_tipo = 'obra' THEN
    RETURN QUERY
    SELECT o2.nombre,
           concat_ws(' · ', u.nombre, o2.localidad, o2.direccion)
    FROM obras o
    CROSS JOIN LATERAL obras_similares_obra(o.nombre, o.direccion, o.localidad, o.id) s
    JOIN obras o2   ON o2.id = s.obra_id
    JOIN usuarios u ON u.id = o2.responsable_id
    WHERE o.id = p_id;

  ELSIF p_tipo = 'empresa' THEN
    RETURN QUERY
    SELECT e2.razon_social,
           concat_ws(' · ', e2.nombre_comercial, e2.localidad)
    FROM obras_empresas e
    CROSS JOIN LATERAL obras_similares_empresa(e.razon_social, e.nombre_comercial, e.id) s
    JOIN obras_empresas e2 ON e2.id = s.empresa_id
    WHERE e.id = p_id;

  ELSIF p_tipo = 'persona' THEN
    RETURN QUERY
    SELECT btrim(p2.nombre || ' ' || coalesce(p2.apellido, '')),
           concat_ws(' · ', s.coincide, u.nombre)
    FROM obras_personas p
    CROSS JOIN LATERAL obras_similares_persona(p.nombre, p.apellido, p.email, p.telefono, p.id) s
    JOIN obras_personas p2 ON p2.id = s.persona_id
    JOIN usuarios u        ON u.id = p2.creado_por
    WHERE p.id = p_id;
  END IF;
END;
$$;

-- ============================================================
-- 12. Resolver
--
-- Un UPDATE dinámico sobre una tabla de lista blanca en vez de cinco copias
-- del mismo statement. Aprobar es soltar la traba; rechazar es desactivar con
-- motivo — nunca DELETE, y la fila queda para explicar el rechazo.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_resolver_pendiente(
  p_tipo    text,
  p_id      uuid,
  p_aprobar boolean,
  p_motivo  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tabla    text;
  v_etiqueta text;
  v_filas    int;
BEGIN
  IF NOT tiene_permiso('obras_aprobar') THEN
    RAISE EXCEPTION 'Sin permiso para resolver autorizaciones' USING ERRCODE = 'OB014';
  END IF;

  v_tabla := CASE p_tipo
    WHEN 'obra'         THEN 'obras'
    WHEN 'empresa'      THEN 'obras_empresas'
    WHEN 'persona'      THEN 'obras_personas'
    WHEN 'obra_empresa' THEN 'obras_obra_empresa'
    WHEN 'obra_persona' THEN 'obras_obra_persona'
  END;

  IF v_tabla IS NULL THEN
    RAISE EXCEPTION 'Tipo de solicitud desconocido' USING ERRCODE = 'OB015';
  END IF;

  IF NOT p_aprobar AND btrim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Un rechazo necesita un motivo: es lo único que va a leer quien la cargó.'
      USING ERRCODE = 'OB016';
  END IF;

  -- Antes del UPDATE: rechazar desactiva la fila, y de una fila desactivada
  -- las etiquetas de vínculo ya no se arman igual.
  v_etiqueta := obras_etiqueta(p_tipo, p_id);

  EXECUTE format(
    'UPDATE %I
        SET pendiente      = false,
            activo         = CASE WHEN $1 THEN activo ELSE false END,
            motivo_rechazo = CASE WHEN $1 THEN NULL ELSE $2 END
      WHERE id = $3 AND pendiente', v_tabla)
  USING p_aprobar, btrim(p_motivo), p_id;

  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas = 0 THEN
    RAISE EXCEPTION 'Esa solicitud ya fue resuelta o no existe' USING ERRCODE = 'OB017';
  END IF;

  INSERT INTO obras_aprobaciones (tipo, registro_id, etiqueta, aprobada, motivo, decidido_por)
  VALUES (p_tipo, p_id, coalesce(v_etiqueta, '(sin nombre)'), p_aprobar, btrim(p_motivo), auth.uid());
END;
$$;

-- ============================================================
-- 13. Historial de decisiones
-- ============================================================
CREATE OR REPLACE FUNCTION obras_historial_aprobaciones(p_dias int DEFAULT 30)
RETURNS TABLE (
  aprobacion_id uuid,
  created_at    timestamptz,
  tipo          text,
  etiqueta      text,
  aprobada      boolean,
  motivo        text,
  decidido_por  text
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_pendientes') THEN
    RAISE EXCEPTION 'Sin permiso para ver las autorizaciones pendientes' USING ERRCODE = 'OB013';
  END IF;

  RETURN QUERY
  SELECT a.id, a.created_at, a.tipo, a.etiqueta, a.aprobada, a.motivo, u.nombre
  FROM obras_aprobaciones a
  JOIN usuarios u ON u.id = a.decidido_por
  WHERE a.created_at >= now() - make_interval(days => greatest(p_dias, 1))
  ORDER BY a.created_at DESC
  LIMIT 500;
END;
$$;

-- ============================================================
-- 14. Submódulos
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden) VALUES
  ('obras_pendientes', 'obras', 'vista', 'Pendientes', 5)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden, vista_id)
SELECT 'obras_aprobar', 'obras', 'funcion', 'Aprobar o rechazar', 1,
       (SELECT id FROM submodulos WHERE codigo = 'obras_pendientes' AND activo)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

-- ============================================================
-- 15. GRANTs — mismo criterio que sql/029: nada para PUBLIC
--
-- `obras_similares_obra` y `obras_similares_persona` no se otorgan a nadie:
-- solo las llaman funciones DEFINER de este módulo, que corren como el dueño.
-- `obras_similares_empresa` sí, porque el envoltorio que la usa es INVOKER.
-- `obras_etiqueta` tampoco: es interna de la cola y del log.
-- ============================================================
REVOKE EXECUTE ON FUNCTION obras_similares_obra(text, text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_similares_empresa(text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_similares_persona(text, text, text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_etiqueta(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_pendientes() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_pendiente_similares(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_resolver_pendiente(text, uuid, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_historial_aprobaciones(int) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION obras_similares_empresa(text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_pendientes() TO authenticated;
GRANT EXECUTE ON FUNCTION obras_pendiente_similares(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_resolver_pendiente(text, uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_historial_aprobaciones(int) TO authenticated;
