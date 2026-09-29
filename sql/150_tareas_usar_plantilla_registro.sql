-- sql/150 — tareas, tramo 5, paso 3: `usar_plantilla` con registro.
--
--   1. Qué marca vale en el texto de un paso: `{dato}` (de `entes.datos`), y
--      en la descripción además `{@registro}`, `{@rol}` y `{si hay rol}…{fin}`
--      / `{si no hay rol}…{fin}` (sin anidar). Sin "Sobre", ninguna. Se suma a
--      `tareas_plantillas_paso_vale`, así que la validan los mismos dos
--      triggers que la condición (TA024).
--   2. `tareas_plantilla_texto(texto, ente, registro, usuario)`: resuelve las
--      marcas con lo que ve ese usuario. `{@…}` pasa a `{ente:uuid|nombre}`.
--   3. `tareas_usar_plantilla_de(..., registro, usuario)`: la interna DEFINER
--      que comparten el uso a mano y el disparo (paso siguiente). Chequea a
--      mano lo que antes decidía la RLS; las reglas de actor de `sql/113`
--      siguen valiendo a profundidad 1. Escribe registro y plantilla en el
--      hilo nuevo; los pasos condicionados que no entran se saltean sin
--      cortar la cadena.
--   4. `usar_plantilla` suma `p_registro` y llama a la interna con auth.uid().
--
-- Decisiones: `decisiones/tareas/catalogo.md` → *Referencias relativas*,
-- *Marcas de rol sin ente*, *La plantilla dice "Sobre"*, *Qué marca vale*,
-- *Las marcas se resuelven con lo que ve quien la usa*.

-- ============================================================
-- 1. Qué marca vale
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_plantilla_marcas_valen(p_sobre text, p_titulo text, p_descripcion text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_datos text[];
  v_roles text[];
  v_marca text;
  v_abierto boolean := false;
BEGIN
  SELECT e.datos, e.roles INTO v_datos, v_roles FROM public.entes e WHERE e.codigo = p_sobre;
  v_datos := coalesce(v_datos, '{}');
  v_roles := coalesce(v_roles, '{}');

  FOR v_marca IN
    SELECT m[1] FROM regexp_matches(coalesce(p_titulo, ''), '\{(@?[a-z_]+|si (?:no )?hay [a-z_]+)\}', 'g') AS m
  LOOP
    IF NOT v_marca = ANY (v_datos) THEN
      RETURN false;
    END IF;
  END LOOP;

  FOR v_marca IN
    SELECT m[1] FROM regexp_matches(coalesce(p_descripcion, ''), '\{(@?[a-z_]+|si (?:no )?hay [a-z_]+)\}', 'g') AS m
  LOOP
    IF v_marca = 'fin' THEN
      IF NOT v_abierto THEN
        RETURN false;
      END IF;
      v_abierto := false;
    ELSIF v_marca LIKE 'si %' THEN
      IF v_abierto OR NOT regexp_replace(v_marca, '^si (no )?hay ', '') = ANY (v_roles) THEN
        RETURN false;
      END IF;
      v_abierto := true;
    ELSIF v_marca LIKE '@%' THEN
      IF NOT ((v_marca = '@registro' AND p_sobre IS NOT NULL) OR substr(v_marca, 2) = ANY (v_roles)) THEN
        RETURN false;
      END IF;
    ELSIF NOT v_marca = ANY (v_datos) THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN NOT v_abierto;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantilla_marcas_valen(text, text, text) FROM PUBLIC, anon, authenticated;

-- La firma suma el texto: se reemplaza, y con ella los dos triggers que la usan.
DROP FUNCTION IF EXISTS public.tareas_plantillas_paso_vale(text, text, public.tipo_evento, text);

CREATE OR REPLACE FUNCTION public.tareas_plantillas_paso_vale(p_sobre text, p_condicion text,
                                                             p_completa_evento public.tipo_evento, p_completa_valor text,
                                                             p_titulo text, p_descripcion text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (p_condicion IS NULL OR public.tareas_plantilla_vale(p_sobre, 'relacion_alta', ltrim(p_condicion, '!')))
     AND (p_completa_evento IS NULL OR public.tareas_plantilla_vale(p_sobre, p_completa_evento, p_completa_valor))
     AND public.tareas_plantilla_marcas_valen(p_sobre, p_titulo, p_descripcion);
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_paso_vale(text, text, public.tipo_evento, text, text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tareas_plantillas_sobre()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.sobre IS DISTINCT FROM OLD.sobre THEN
    IF NEW.sobre IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.entes e
      WHERE e.codigo = NEW.sobre AND e.activo AND public.usuario_tiene_permiso(auth.uid(), e.submodulo)
    ) THEN
      RAISE EXCEPTION 'No ves ese ente' USING ERRCODE = 'TA023';
    END IF;

    IF TG_OP = 'UPDATE' AND EXISTS (
      SELECT 1 FROM public.tareas_plantillas_pasos p
      WHERE p.plantilla_id = NEW.id AND p.activo
        AND NOT public.tareas_plantillas_paso_vale(NEW.sobre, p.condicion, p.completa_evento, p.completa_valor,
                                                   p.titulo, p.descripcion)
    ) THEN
      RAISE EXCEPTION 'Un paso no vale para ese ente' USING ERRCODE = 'TA024';
    END IF;
  END IF;

  IF NEW.disparo_evento IS NOT NULL AND NOT (
    EXISTS (SELECT 1 FROM public.entes e WHERE e.codigo = NEW.sobre AND NEW.disparo_evento = ANY (e.disparos))
    AND public.tareas_plantilla_vale(NEW.sobre, NEW.disparo_evento, NEW.disparo_estado)
  ) THEN
    RAISE EXCEPTION 'Ese disparo no vale para el ente' USING ERRCODE = 'TA024';
  END IF;

  IF NEW.disparo_activo AND (TG_OP = 'INSERT' OR NOT OLD.disparo_activo)
     AND NEW.dueno_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Activar el disparo es de su dueño' USING ERRCODE = 'TA025';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.tareas_plantillas_pasos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tareas_plantillas_paso_vale(
    (SELECT sobre FROM public.tareas_plantillas WHERE id = NEW.plantilla_id),
    NEW.condicion, NEW.completa_evento, NEW.completa_valor, NEW.titulo, NEW.descripcion
  ) THEN
    RAISE EXCEPTION 'Un paso no vale para el ente de la plantilla' USING ERRCODE = 'TA024';
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 2. Resolver el texto
-- ============================================================
-- Primero los `{si…}`, después los datos (copia: sus llaves pasan a
-- paréntesis para no armar marcas ni referencias), al final las `{@…}`.
-- "Hay rol" es que el registro tenga el vínculo, como la condición del paso;
-- `{@rol}` nombra solo lo que el usuario ve.
CREATE OR REPLACE FUNCTION public.tareas_plantilla_texto(p_texto text, p_ente text, p_registro uuid, p_usuario uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := p_texto;
  v_e public.entes;
  v_tiene text[];
  v_rol text;
  v_dato text;
  v_valor text;
BEGIN
  IF p_texto IS NULL OR p_ente IS NULL OR position('{' IN p_texto) = 0 THEN
    RETURN p_texto;
  END IF;

  SELECT * INTO v_e FROM public.entes WHERE codigo = p_ente;
  v_tiene := ARRAY(SELECT DISTINCT r.rol FROM public.relacionados_de_registro_de(p_ente, p_registro, p_usuario) r);

  FOREACH v_rol IN ARRAY v_e.roles LOOP
    v := regexp_replace(v, '\{si hay ' || v_rol || '\}((?:[^{]|\{(?!fin\}))*)\{fin\}',
                        CASE WHEN v_rol = ANY (v_tiene) THEN '\1' ELSE '' END, 'g');
    v := regexp_replace(v, '\{si no hay ' || v_rol || '\}((?:[^{]|\{(?!fin\}))*)\{fin\}',
                        CASE WHEN v_rol = ANY (v_tiene) THEN '' ELSE '\1' END, 'g');
  END LOOP;

  FOREACH v_dato IN ARRAY v_e.datos LOOP
    IF position('{' || v_dato || '}' IN v) > 0 THEN
      EXECUTE format('SELECT %I::text FROM %s WHERE id = $1', v_dato, v_e.tabla) INTO v_valor USING p_registro;
      v := replace(v, '{' || v_dato || '}', translate(coalesce(v_valor, ''), '{}', '()'));
    END IF;
  END LOOP;

  v := replace(v, '{@registro}', format('{%s:%s|%s}', p_ente, p_registro,
                                        replace(public.etiqueta_registro_de(p_ente, p_registro, p_usuario), '}', '')));

  FOREACH v_rol IN ARRAY v_e.roles LOOP
    IF position('{@' || v_rol || '}' IN v) > 0 THEN
      v := replace(v, '{@' || v_rol || '}', coalesce((
        SELECT string_agg(format('{%s:%s|%s}', x.ente, x.registro_id, replace(x.nombre, '}', '')), ', ' ORDER BY x.nombre)
        FROM (
          SELECT DISTINCT r.ente, r.registro_id, public.etiqueta_registro_de(r.ente, r.registro_id, p_usuario) AS nombre
          FROM public.relacionados_de_registro_de(p_ente, p_registro, p_usuario) r
          WHERE r.rol = v_rol
        ) x
        WHERE x.nombre IS NOT NULL
      ), ''));
    END IF;
  END LOOP;

  RETURN v;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantilla_texto(text, text, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 3. La interna
-- ============================================================
-- DEFINER: escribe el registro del hilo (fuera de los GRANT) y la usa el
-- disparo, que corre con otro auth.uid(). Lo que antes decía la RLS —ver la
-- plantilla, ver el hilo al que suma— se chequea acá con `p_usuario`. El
-- responsable del hilo nuevo es `p_usuario`: a mano es quien la usa (TA002
-- sigue valiendo), en el disparo el dueño del registro.
CREATE OR REPLACE FUNCTION public.tareas_usar_plantilla_de(
  p_plantilla uuid,
  p_titulo    text,
  p_hilo      uuid,
  p_asignados jsonb,
  p_registro  uuid,
  p_usuario   uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p public.tareas_plantillas;
  v_hilo uuid := COALESCE(p_hilo, gen_random_uuid());
  v_tiene text[];
  v_paso public.tareas_plantillas_pasos;
  v_elegido jsonb;
  v_usuario uuid;
  v_equipo uuid;
  v_id uuid;
  v_anterior uuid;
  v_previo uuid;
BEGIN
  SELECT * INTO v_p FROM public.tareas_plantillas p
  WHERE p.id = p_plantilla AND p.activo
    AND (p.dueno_id = p_usuario OR public.usuario_tiene_permiso(p_usuario, 'tareas_administrar'))
    AND public.tareas_puede_ver_plantilla_de(p.dueno_id, p.publicada, p.activo, p.sobre, p_usuario);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La plantilla no existe o no es tuya' USING ERRCODE = 'TA017';
  END IF;

  IF (v_p.sobre IS NULL) <> (p_registro IS NULL)
     OR (p_registro IS NOT NULL AND NOT public.puede_abrir_registro(v_p.sobre, p_registro, p_usuario)) THEN
    RAISE EXCEPTION 'Elegí un registro que veas' USING ERRCODE = 'TA026';
  END IF;

  IF p_hilo IS NULL THEN
    INSERT INTO public.tareas_hilos (id, titulo, responsable_id, registro_ente, registro_id, plantilla_id)
    VALUES (v_hilo, COALESCE(NULLIF(btrim(p_titulo), ''), v_p.nombre), p_usuario,
            v_p.sobre, p_registro, CASE WHEN v_p.sobre IS NOT NULL THEN v_p.id END);
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.tareas_hilos h
    WHERE h.id = p_hilo AND public.tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, p_usuario)
  ) THEN
    RAISE EXCEPTION 'El hilo no existe o no lo ves' USING ERRCODE = '42501';
  END IF;

  IF v_p.sobre IS NOT NULL THEN
    v_tiene := ARRAY(SELECT DISTINCT r.rol FROM public.relacionados_de_registro_de(v_p.sobre, p_registro, p_usuario) r);
  END IF;

  FOR v_paso IN
    SELECT * FROM public.tareas_plantillas_pasos
    WHERE plantilla_id = v_p.id AND activo
    ORDER BY orden
  LOOP
    v_previo := CASE WHEN v_paso.espera_anterior THEN v_anterior END;

    -- Un paso que no entra no corta la cadena: el siguiente espera al previo.
    IF v_paso.condicion IS NOT NULL
       AND (ltrim(v_paso.condicion, '!') = ANY (v_tiene)) = (v_paso.condicion LIKE '!%') THEN
      v_anterior := v_previo;
      CONTINUE;
    END IF;

    v_elegido := p_asignados -> v_paso.id::text;
    v_usuario := (v_elegido ->> 'asignado_id')::uuid;
    v_equipo := (v_elegido ->> 'asignado_equipo_id')::uuid;

    IF v_usuario IS NULL AND v_equipo IS NULL THEN
      IF (v_paso.asignado_id IS NOT NULL OR v_paso.asignado_equipo_id IS NOT NULL)
         AND public.tareas_puede_recibir(v_paso.asignado_id, v_paso.asignado_equipo_id) THEN
        v_usuario := v_paso.asignado_id;
        v_equipo := v_paso.asignado_equipo_id;
      ELSE
        v_usuario := p_usuario;
      END IF;
    END IF;

    v_id := gen_random_uuid();

    INSERT INTO public.tareas (id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id,
                               asignado_equipo_id, prioridad, vence, vence_dias)
    VALUES (v_id, v_hilo, v_previo,
            left(public.tareas_plantilla_texto(v_paso.titulo, v_p.sobre, p_registro, p_usuario), 500),
            left(public.tareas_plantilla_texto(v_paso.descripcion, v_p.sobre, p_registro, p_usuario), 5000),
            v_usuario, v_equipo, v_paso.prioridad,
            CASE WHEN v_previo IS NULL THEN public.tareas_hoy() + v_paso.vence_dias END,
            CASE WHEN v_previo IS NOT NULL THEN v_paso.vence_dias END);

    v_anterior := v_id;
  END LOOP;

  RETURN v_hilo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_usar_plantilla_de(uuid, text, uuid, jsonb, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. usar_plantilla
-- ============================================================
DROP FUNCTION IF EXISTS public.usar_plantilla(uuid, text, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.usar_plantilla(
  p_plantilla uuid,
  p_titulo    text DEFAULT NULL,
  p_hilo      uuid DEFAULT NULL,
  p_asignados jsonb DEFAULT '{}',
  p_registro  uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.tareas_usar_plantilla_de(p_plantilla, p_titulo, p_hilo, COALESCE(p_asignados, '{}'), p_registro, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, jsonb, uuid) TO authenticated;
