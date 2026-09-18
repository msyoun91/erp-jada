-- sql/093 — otorgada_por es historia, no autoridad
--
-- El segundo cambio estructural que sql/090 dejó a mitad, hermano de sql/092 y
-- de la misma auditoría de compartir/transferir.
--
-- EL PROBLEMA. Quién ve una fila en la vista Compartido y quién puede revocarla
-- son hoy dos respuestas distintas. La vista lista por `otorgada_por =
-- auth.uid()`; revocar pide el dueño del ancla (sql/090). Como las dos tenían
-- que coincidir igual, transferir y migrar iban reescribiendo `otorgada_por`
-- con cinco UPDATE para empujar la columna detrás de la propiedad. Una
-- transferencia mal apuntada movía *quién puede revocar*: el mecanismo exacto
-- de V1.
--
-- LA PREMISA DEL BACKLOG ERA FALSA. Decía "derivar las dos del ancla
-- (responsable de la obra / dueño de la empresa)". No se puede: en dos de las
-- cuatro clases de grant contextual el dueño del ancla ES el receptor.
--
--   · cascada de `obras_transferir` → el receptor ve los contactos que NO
--     migran, anclados a la obra que sí cambió de mano: el ancla es suya.
--   · recíproco del estado 2 (sql/087) → el saliente sigue viendo lo que se
--     fue, anclado a SUS obras y empresas: el ancla también es suya.
--
-- Derivar del ancla habría puesto esas filas en la vista Compartido del propio
-- receptor —"le compartí esto a mí mismo"— y se las habría sacado a quien
-- expone el contacto.
--
-- LA REGLA QUE SÍ ES INVARIANTE. `otorgada_por`, al nacer, es siempre el dueño
-- de la entidad compartida. Lo exigen los cuatro escritores: el checklist de
-- `obras_compartir_obra` y las tres ramas de `obras_compartir_registros` piden
-- `creado_por = auth.uid()`; la cascada de `obras_transferir` otorga con
-- `v_actual`, que es de quien sigue siendo el contacto; el recíproco otorga con
-- `p_a_usuario`, que es de quien pasó a serlo. sql/045 ya lo había escrito con
-- todas las letras —*"quien otorgó es siempre el dueño"*— y usó la columna como
-- atajo para no recursar contra `obras_personas` / `obras_empresas`.
--
-- Entonces no hace falta ninguna regla nueva: la autoridad es la propiedad, y
-- la columna era su sombra. Se lee la propiedad y se dejan de escribir los
-- cinco UPDATE. sql/085 ya lo había hecho para la tabla que nació última —la
-- policy de `obras_empresa_grant_contextual` deriva de `e.creado_por`—; las
-- otras dos se quedaron en el atajo.
--
-- LA AUTORIDAD ES DE DOS LADOS, Y SE ESCRIBE UNA VEZ. Sobre un grant contextual
-- manda el dueño de la entidad —es su contacto el que se ve— **o** el dueño del
-- ancla —es su obra o su empresa la que lo muestra—. Son la misma persona en el
-- checklist y se separan cuando la obra cambia de mano y el contacto no.
-- Reemplaza a "dueño del ancla o quien otorgó", que era el mismo conjunto
-- mientras nadie reescribiera la columna.
--
-- `obras_ctx_autoridad(tipo, entidad, ancla_tipo, ancla)` es esa regla, y la
-- leen los tres lugares que antes decían cosas distintas: la vista Compartido,
-- `obras_revocar_contextual` y las policies de las tablas de grant. Que la
-- entrada del backlog empiece con *"quién ve la fila y quién puede revocarla
-- siguen siendo dos respuestas distintas"* pide exactamente eso: una función.
--
-- **La primera versión de esta migración ató la vista solo al dueño de la
-- entidad, y estaba mal.** Lo encontró `sql/tests/obras_090.sql` al correrlo: A
-- comparte su obra O con B tildando su contacto P, y después transfiere P a C.
-- Con la vista colgada de la entidad, A —responsable de O, que es el vehículo
-- de esa exposición— dejaba de ver la fila y C la veía colgada de una obra que
-- no es suya. Además rompía el anidado de la vista, que asume que el padre
-- (la obra compartida) viaja en el mismo resultado que sus hijos.
--
-- La vista lista entonces lo que puedo revocar, menos aquello donde YO soy el
-- receptor: una fila que me otorgaron no es algo que compartí.
--
-- LO QUE ESTO ARREGLA, ADEMÁS DE CERRAR LA CLASE:
--
--   · `getCompartidosObra` (queries.ts) lee `obras_obra_compartida` directo y
--     su comentario dice "solo lo ve el responsable". La policy decía otra cosa
--     —`otorgada_por`— y coincidían solo porque transferir reescribía. Sacar el
--     UPDATE sin tocar la policy dejaba al nuevo responsable con el panel
--     vacío y el tercero adentro. Ahora la policy dice lo que el comentario.
--   · el dueño de un contacto que no migró deja de perderlo de vista cuando la
--     obra cambia de mano: hoy `otorgada_por` pasa al receptor de la obra y el
--     dueño del contacto no ve ni puede revocar su propia exposición.
--   · el checklist deja de poder apagar lo que no puede ofrecer: filtraba por
--     `otorgada_por = auth.uid()` y ahora por dueño de la entidad, que es
--     exactamente el universo que la pantalla muestra.
--   · revocar dos veces deja de mentir: con la autoridad preguntada una vez y
--     antes del UPDATE, cero filas es idempotencia y no OB026.
--
-- EL CHECK SE QUEDA. La otra premisa del backlog —"el CHECK `usuario_id <>
-- otorgada_por` deja de proteger nada"— también es falsa. La columna se sigue
-- escribiendo con el dueño de la entidad, así que el CHECK sigue siendo el
-- guard de inserción "nadie se comparte consigo mismo", ahora sin nadie que lo
-- mueva por detrás. Lo que cambia no es quién lo escribe: es que nadie lo lee
-- para decidir. `obras_migrar_agenda` 3.4 (ex 3.5) además depende de él.
--
-- DERIVA. `obras_revocar_contextual` vivía en la base sin sus comentarios —la
-- "versión despojada" que documenta la entrada cerrada del BACKLOG.md, misma
-- clase que sql/091 encontró en otras tres—. La lógica era idéntica; se
-- reescribe con el texto del repo y queda alineada.
--
-- Filas con `otorgada_por` distinto del dueño al escribir esto: 0 de 4 activas.
-- No hay backfill: no hay nada que corregir.
--
-- Test: sql/tests/obras_093.sql

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · La autoridad, una sola vez
-- ─────────────────────────────────────────────────────────────────────────────

-- Hermana de `obras_ctx_vigente` (sql/092), y por el mismo motivo: la regla
-- estaba escrita de tres formas distintas —`otorgada_por` en la vista, "ancla o
-- otorgante" en el revoke, `otorgada_por` otra vez en las policies— y ninguna
-- era la regla. No pregunta si el grant existe ni si está vigente: pregunta
-- quién manda sobre él.
--
-- No mira el grant, así que no puede recursar contra las tablas de grant: por
-- eso puede vivir adentro de sus policies, que es lo que sql/045 no podía hacer
-- con un EXISTS inline.
CREATE OR REPLACE FUNCTION obras_ctx_autoridad(
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
  SELECT
    -- El dueño del contacto: es su teléfono el que se está viendo.
    CASE p_tipo
      WHEN 'empresa' THEN EXISTS (
        SELECT 1 FROM public.obras_empresas e
        WHERE e.id = p_entidad_id AND e.creado_por = (select auth.uid()))
      WHEN 'persona' THEN EXISTS (
        SELECT 1 FROM public.obras_personas p
        WHERE p.id = p_entidad_id AND p.creado_por = (select auth.uid()))
      ELSE false
    END
    OR
    -- El dueño del ancla: es su obra o su empresa la que lo muestra.
    CASE p_ancla_tipo
      WHEN 'obra' THEN EXISTS (
        SELECT 1 FROM public.obras o
        WHERE o.id = p_ancla_id AND o.responsable_id = (select auth.uid()))
      WHEN 'empresa' THEN EXISTS (
        SELECT 1 FROM public.obras_empresas e
        WHERE e.id = p_ancla_id AND e.creado_por = (select auth.uid()))
      ELSE false
    END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_ctx_autoridad(text, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_ctx_autoridad(text, uuid, text, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · La vista Compartido lista lo que puedo revocar
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE (
  tipo           text,
  entidad_id     uuid,
  entidad_nombre text,
  usuario_id     uuid,
  usuario_nombre text,
  origen_tipo    text,
  origen_id      uuid,
  origen_nombre  text,
  compartida_el  timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  -- Una obra la comparte su responsable. Antes `otorgada_por = auth.uid()`, que
  -- es lo mismo hasta que la obra cambia de mano — y por eso transferir tenía
  -- que ir reescribiendo la columna para que la fila no se le perdiera al que
  -- recibe.
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE o.responsable_id = auth.uid() AND c.activo

  UNION ALL
  -- Un contextual lo lista quien manda sobre él: el dueño del contacto o el del
  -- ancla. `usuario_id <> auth.uid()` saca las filas donde soy el receptor —la
  -- cascada de transferir y el recíproco del estado 2 anclan el grant en algo
  -- del receptor, y "me lo compartí a mí" no es una fila de esta pantalla.
  SELECT 'empresa'::text, g.empresa_id, e.razon_social, g.usuario_id, u.nombre,
         'obra'::text, g.obra_id,
         (SELECT nombre FROM obras WHERE id = g.obra_id),
         g.created_at
  FROM obras_empresa_grant_contextual g
  JOIN obras_empresas e ON e.id = g.empresa_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.activo AND g.usuario_id <> auth.uid()
    AND obras_ctx_autoridad('empresa', g.empresa_id, 'obra', g.obra_id)

  UNION ALL
  SELECT 'persona'::text, g.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         g.usuario_id, u.nombre,
         CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
         coalesce(g.obra_id, g.empresa_id),
         CASE WHEN g.obra_id IS NOT NULL
              THEN (SELECT nombre FROM obras WHERE id = g.obra_id)
              ELSE (SELECT razon_social FROM obras_empresas WHERE id = g.empresa_id) END,
         g.created_at
  FROM obras_persona_grant_contextual g
  JOIN obras_personas p ON p.id = g.persona_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.activo AND g.usuario_id <> auth.uid()
    AND obras_ctx_autoridad('persona', g.persona_id,
          CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
          coalesce(g.obra_id, g.empresa_id))

  ORDER BY 9 DESC
  LIMIT 500;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · Revocar un contextual pregunta lo mismo que la vista
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_revocar_contextual(
  p_tipo        text,
  p_entidad_id  uuid,
  p_usuario_id  uuid,
  p_ancla_tipo  text,
  p_ancla_id    uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_tipo NOT IN ('empresa', 'persona')
     OR p_ancla_tipo NOT IN ('obra', 'empresa')
     -- Una empresa no cuelga de otra empresa: su ancla es siempre una obra.
     OR (p_tipo = 'empresa' AND p_ancla_tipo = 'empresa') THEN
    RAISE EXCEPTION 'Combinación de tipo y ancla inválida' USING ERRCODE = 'OB031';
  END IF;

  -- La autoridad ya no es una columna de la fila, así que se pregunta una vez,
  -- antes del UPDATE, y con la misma función que la vista. De paso deja de
  -- mentir: con el gate adentro del WHERE, cero filas era OB026 —"no podés
  -- revocar"— incluso para quien sí podía y estaba reintentando sobre algo ya
  -- revocado. Ahora cero filas es idempotencia y el error habla de autoridad.
  IF NOT obras_ctx_autoridad(p_tipo, p_entidad_id, p_ancla_tipo, p_ancla_id) THEN
    RAISE EXCEPTION 'Solo el dueño del contacto, o el de la obra o empresa desde la que se ve, puede revocar el acceso'
      USING ERRCODE = 'OB026';
  END IF;

  IF p_tipo = 'empresa' THEN
    UPDATE obras_empresa_grant_contextual
      SET activo = false, updated_at = now()
      WHERE empresa_id = p_entidad_id AND usuario_id = p_usuario_id
        AND obra_id = p_ancla_id AND activo;
  ELSIF p_ancla_tipo = 'obra' THEN
    UPDATE obras_persona_grant_contextual
      SET activo = false, updated_at = now()
      WHERE persona_id = p_entidad_id AND usuario_id = p_usuario_id
        AND obra_id = p_ancla_id AND activo;
  ELSE
    UPDATE obras_persona_grant_contextual
      SET activo = false, updated_at = now()
      WHERE persona_id = p_entidad_id AND usuario_id = p_usuario_id
        AND empresa_id = p_ancla_id AND activo;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4 · El checklist solo apaga lo que puede ofrecer
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

  -- Estado deseado (sql/049): lo destildado se apaga, por ancla. Acotado a lo
  -- mío por dueño y no por `otorgada_por`: la pantalla solo ofrece mis
  -- contactos, así que solo puede apagar mis contactos. Un grant sobre el
  -- contacto de otro anclado a esta obra —queda cuando la obra cambia de mano y
  -- el contacto no— no aparece en el checklist, y por lo tanto no puede caerse
  -- por no estar tildado.
  UPDATE obras_empresa_grant_contextual g
    SET activo = false, updated_at = now()
    WHERE g.obra_id = p_obra_id AND g.usuario_id = p_usuario_id AND g.activo
      AND NOT (g.empresa_id = ANY(p_empresas))
      AND EXISTS (SELECT 1 FROM obras_empresas e
                  WHERE e.id = g.empresa_id AND e.creado_por = auth.uid());

  UPDATE obras_persona_grant_contextual g
    SET activo = false, updated_at = now()
    WHERE g.obra_id = p_obra_id AND g.usuario_id = p_usuario_id AND g.activo
      AND NOT (g.persona_id = ANY(p_personas))
      AND EXISTS (SELECT 1 FROM obras_personas p
                  WHERE p.id = g.persona_id AND p.creado_por = auth.uid());
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5 · Transferir deja de mover el otorgante
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

  -- Acá había tres UPDATE de `otorgada_por` (sql/090): lo compartido con
  -- terceros pasaba a colgar del nuevo dueño para que alguien pudiera revocarlo
  -- y para que no desapareciera de la vista Compartido. No hacen falta más. Lo
  -- que la obra comparte lo revoca y lo ve su responsable, que a partir de la
  -- línea de arriba es el receptor; lo contextual sobre contactos que no
  -- migraron lo sigue viendo y revocando su dueño, que es quien expone el
  -- teléfono. La columna queda como el log de quién otorgó, y nada la mueve.
  --
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

  -- Acá había un cuarto UPDATE de `otorgada_por`, el de las personas ancladas
  -- en esta empresa. Mismo motivo que en `obras_transferir`: la autoridad sobre
  -- un contextual es el dueño del contacto y el del ancla, y los dos se leen de
  -- su tabla.

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
-- 6 · Migrar la agenda, lo mismo
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
  -- Mismo saneo que hace `obras_transferir` al cambiar de dueño una obra. Es
  -- también lo que absorbe el bloque que se fue (ver 3.4): después de 3.1 todo
  -- lo del saliente es del entrante, así que "apagar lo que el saliente le
  -- otorgó al entrante" y "apagar lo que el entrante recibió sobre lo suyo" son
  -- el mismo conjunto — y este lo dice por propiedad, no por `otorgada_por`.
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

  -- ---- 3.4 Lo que el saliente recibió ----
  -- Tres pasos por tabla, y el orden importa:
  --   a) si el entrante ya tiene fila para la misma llave, se revive la suya —
  --      el UNIQUE no admite dos y mover la del saliente fallaría;
  --   b) se apaga lo del saliente que no puede moverse: la llave ya la ocupa el
  --      entrante, o el otorgante ES el entrante (nadie se comparte consigo
  --      mismo);
  --   c) el resto cambia de mano.
  -- El EXISTS de (b) no filtra por `activo`: el UNIQUE tampoco. El
  -- `otorgada_por` de (b) es la última lectura que queda de la columna y no
  -- decide autoridad: detecta la fila que el entrante le había otorgado al
  -- saliente, que al mover `usuario_id` violaría el CHECK.
  --
  -- (Antes de este bloque iba "lo que el saliente otorgó", seis UPDATE sobre
  -- `otorgada_por`. Se fue entero: las tres mitades que apagaban son 3.3 dicho
  -- por la columna equivocada, y las tres que reescribían el otorgante ya no le
  -- cambian la autoridad a nadie.)
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 7 · Las tres policies de grant dicen la misma regla
-- ─────────────────────────────────────────────────────────────────────────────

-- sql/045 acotó las tres policies de grant a `usuario_id = auth.uid() OR
-- otorgada_por = auth.uid()` para salir de una recursión infinita (42P17), y
-- dejó escrito por qué alcanzaba: *"quien otorgó es siempre el dueño"*. La
-- columna era el atajo para no volver a `obras` / `obras_personas`. sql/085
-- escribió la tabla nueva sin el atajo —`empresa_grant_ctx_select` ya deriva de
-- `e.creado_por`— y estas dos se quedaron.
--
-- No es cosmético: `getCompartidosObra` (queries.ts) lee esta tabla directo
-- para el panel "compartida con" de la ficha, y su comentario dice "solo lo ve
-- el responsable". Con el otorgante fijo y la sección 5 sin reescrituras, el
-- nuevo responsable de una obra transferida veía el panel vacío mientras el
-- tercero seguía adentro.
--
-- La recursión se esquiva como entonces, con DEFINER: `obras_es_mi_obra` para
-- la tabla de la obra y `obras_ctx_autoridad` para las dos de grant, que no
-- miran ninguna tabla de grant.
--
-- Las tres pasan a decir lo mismo que la vista y el revoke — leer la fila del
-- log es el tercer lado de la misma autoridad. La de empresa (sql/085) gana el
-- ancla, que le faltaba: derivaba solo del dueño de la entidad.
--
-- `obras_es_mi_obra` pide además `o.activo`: los compartidos de una obra
-- desactivada dejan de leerse por PostgREST directo. La ficha de una obra
-- desactivada no es alcanzable, y la vista Compartido no los pierde — es
-- DEFINER y mira `responsable_id`.

DROP POLICY IF EXISTS obra_compartida_select ON obras_obra_compartida;
CREATE POLICY obra_compartida_select ON obras_obra_compartida FOR SELECT
  USING (usuario_id = (select auth.uid()) OR obras_es_mi_obra(obra_id));

DROP POLICY IF EXISTS grant_ctx_select ON obras_persona_grant_contextual;
CREATE POLICY grant_ctx_select ON obras_persona_grant_contextual FOR SELECT
  USING (
    usuario_id = (select auth.uid())
    OR obras_ctx_autoridad(
         'persona', persona_id,
         CASE WHEN obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
         coalesce(obra_id, empresa_id))
  );

DROP POLICY IF EXISTS empresa_grant_ctx_select ON obras_empresa_grant_contextual;
CREATE POLICY empresa_grant_ctx_select ON obras_empresa_grant_contextual FOR SELECT
  USING (
    usuario_id = (select auth.uid())
    OR obras_ctx_autoridad('empresa', empresa_id, 'obra', obra_id)
  );

COMMIT;
