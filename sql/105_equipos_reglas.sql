-- sql/105 — equipos y delegación: las reglas.
--
-- `sql/104` dejó el esquema; acá va todo lo que lo hace valer: techo, un
-- delegador por equipo, cascadas y heredero. Decisión: `decisiones/usuarios.md`
-- → *Equipos y delegación de permisos*. Verificado con
-- `sql/tests/usuarios_equipos.sql`.
--
-- Las reglas son triggers, no chequeos de las funciones: el admin escribe con
-- `service_role` (que se saltea la RLS pero no los triggers) y el delegador con
-- su sesión, así que la misma regla cubre las dos vías y también el PostgREST
-- directo.
--
-- Qué es una fila delegada: la que otorgó un miembro de un equipo. Un admin
-- nunca es miembro, así que no hace falta una columna que lo marque.
--
-- Los mensajes van con clase `US`: están escritos para el usuario y
-- `mensajeError()` los deja pasar.

-- ============================================================
-- Catálogo: las funciones de usuarios nunca se delegan
-- ============================================================
-- Es lo que impide la cadena: `usuarios_delegar` y `usuarios_equipo` los da
-- solo el admin.
ALTER TABLE public.submodulos DROP CONSTRAINT IF EXISTS submodulos_usuarios_no_delegable;
ALTER TABLE public.submodulos ADD CONSTRAINT submodulos_usuarios_no_delegable
  CHECK (NOT (delegable AND modulo = 'usuarios'));

-- ============================================================
-- Helpers — sin GRANT: los llaman los triggers y las funciones de admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.usuario_tiene_permiso(p_usuario uuid, p_codigo text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.usuario_submodulos us
    JOIN public.submodulos s ON s.id = us.submodulo_id
    JOIN public.usuarios u ON u.id = us.usuario_id
    WHERE us.usuario_id = p_usuario
      AND u.activo
      AND us.activo
      AND s.activo
      AND s.codigo = p_codigo
  );
$$;

REVOKE EXECUTE ON FUNCTION public.usuario_tiene_permiso(uuid, text) FROM PUBLIC, anon, authenticated;

-- El predicado vive en un solo lugar, como en `sql/062`. Mismo cuerpo que el
-- de `sql/102`, incluido `u.activo`: verificable con `usuarios_activo.sql`.
CREATE OR REPLACE FUNCTION tiene_permiso(p_codigo text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(auth.uid(), p_codigo);
$$;

CREATE OR REPLACE FUNCTION public.equipo_de(p_usuario uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT m.equipo_id
  FROM public.equipos_miembros m
  JOIN public.equipos e ON e.id = m.equipo_id
  WHERE m.usuario_id = p_usuario
    AND m.activo
    AND e.activo;
$$;

REVOKE EXECUTE ON FUNCTION public.equipo_de(uuid) FROM PUBLIC, anon, authenticated;

-- Mismo cuerpo que `equipo_de`, para quien llama.
CREATE OR REPLACE FUNCTION public.mi_equipo()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT public.equipo_de(auth.uid());
$$;

-- ============================================================
-- usuario_submodulos — invariantes, al cierre de la transacción
-- ============================================================
-- Diferido porque varias escrituras pasan por estados intermedios inválidos:
-- vista y función en el mismo upsert, o el heredero que recibe
-- `usuarios_delegar` antes de que el saliente lo pierda. Por eso relee la fila
-- en vez de confiar en NEW: importa cómo quedó, no cómo la dejó el statement.
CREATE OR REPLACE FUNCTION public.usuario_submodulos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  f public.usuario_submodulos;
  s public.submodulos;
  v_equipo uuid;
BEGIN
  SELECT * INTO f FROM public.usuario_submodulos WHERE id = NEW.id;
  SELECT * INTO s FROM public.submodulos WHERE id = f.submodulo_id;

  IF NOT f.activo THEN
    IF s.tipo = 'vista' AND EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.submodulos fn ON fn.id = us.submodulo_id
      WHERE us.usuario_id = f.usuario_id AND us.activo AND fn.vista_id = s.id
    ) THEN
      RAISE EXCEPTION 'Cada función requiere que su vista esté autorizada' USING ERRCODE = 'US001';
    END IF;
    RETURN NULL;
  END IF;

  IF s.tipo = 'funcion' AND NOT EXISTS (
    SELECT 1 FROM public.usuario_submodulos
    WHERE usuario_id = f.usuario_id AND submodulo_id = s.vista_id AND activo
  ) THEN
    RAISE EXCEPTION 'Cada función requiere que su vista esté autorizada' USING ERRCODE = 'US001';
  END IF;

  v_equipo := public.equipo_de(f.usuario_id);

  IF s.codigo = 'usuarios_gestionar' AND v_equipo IS NOT NULL THEN
    RAISE EXCEPTION 'Quien administra usuarios no puede ser miembro de un equipo' USING ERRCODE = 'US002';
  END IF;

  IF s.codigo = 'usuarios_delegar' THEN
    IF v_equipo IS NULL THEN
      RAISE EXCEPTION 'El delegador tiene que ser miembro de un equipo' USING ERRCODE = 'US003';
    END IF;

    -- Serializa dos designaciones concurrentes en el mismo equipo.
    PERFORM 1 FROM public.equipos WHERE id = v_equipo FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.equipos_miembros m ON m.usuario_id = us.usuario_id AND m.activo
      WHERE m.equipo_id = v_equipo
        AND us.submodulo_id = s.id
        AND us.activo
        AND us.usuario_id <> f.usuario_id
    ) THEN
      RAISE EXCEPTION 'El equipo ya tiene un delegador' USING ERRCODE = 'US004';
    END IF;
  END IF;

  -- El techo, para las filas delegadas.
  IF f.otorgada_por IS NOT NULL AND public.equipo_de(f.otorgada_por) IS NOT NULL THEN
    IF f.otorgada_por = f.usuario_id OR v_equipo IS DISTINCT FROM public.equipo_de(f.otorgada_por) THEN
      RAISE EXCEPTION 'Solo se delega a otro miembro del mismo equipo' USING ERRCODE = 'US005';
    END IF;
    IF NOT public.usuario_tiene_permiso(f.otorgada_por, 'usuarios_delegar') THEN
      RAISE EXCEPTION 'Solo el delegador del equipo puede delegar permisos' USING ERRCODE = 'US006';
    END IF;
    IF NOT s.delegable THEN
      RAISE EXCEPTION 'Ese permiso no es delegable' USING ERRCODE = 'US007';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.usuario_submodulos
      WHERE usuario_id = f.otorgada_por AND submodulo_id = s.id AND activo
    ) THEN
      RAISE EXCEPTION 'El delegador no puede dar un permiso que no tiene' USING ERRCODE = 'US008';
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.usuario_submodulos_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS usuario_submodulos_validar ON public.usuario_submodulos;
CREATE CONSTRAINT TRIGGER usuario_submodulos_validar
  AFTER INSERT OR UPDATE ON public.usuario_submodulos
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.usuario_submodulos_validar();

-- ============================================================
-- usuario_submodulos — revocar en cascada
-- ============================================================
-- Inmediato: lo que un delegador pierde lo pierden en el acto quienes lo
-- recibieron de él. Solo para miembros: el admin no es miembro, y lo que otorgó
-- no cuelga de sus propios permisos.
CREATE OR REPLACE FUNCTION public.usuario_submodulos_cascada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_equipo uuid := public.equipo_de(NEW.usuario_id);
  v_codigo text;
BEGIN
  IF v_equipo IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT codigo INTO v_codigo FROM public.submodulos WHERE id = NEW.submodulo_id;

  IF v_codigo = 'usuarios_delegar' THEN
    -- Sale el delegador. Sin heredero ya designado, solo si no queda nadie
    -- que pueda serlo: `quitar_delegador` le da la función al heredero antes
    -- de sacársela al saliente.
    IF NOT EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.equipos_miembros m ON m.usuario_id = us.usuario_id AND m.activo
      WHERE m.equipo_id = v_equipo
        AND us.submodulo_id = NEW.submodulo_id
        AND us.activo
        AND us.usuario_id <> NEW.usuario_id
    ) AND EXISTS (
      SELECT 1
      FROM public.equipos_miembros m
      JOIN public.usuarios u ON u.id = m.usuario_id AND u.activo
      WHERE m.equipo_id = v_equipo AND m.activo AND m.usuario_id <> NEW.usuario_id
    ) THEN
      RAISE EXCEPTION 'Para sacar al delegador hay que elegir un heredero' USING ERRCODE = 'US009';
    END IF;

    UPDATE public.usuario_submodulos SET activo = false
    WHERE otorgada_por = NEW.usuario_id AND activo;
  ELSE
    UPDATE public.usuario_submodulos SET activo = false
    WHERE otorgada_por = NEW.usuario_id AND submodulo_id = NEW.submodulo_id AND activo;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.usuario_submodulos_cascada() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS usuario_submodulos_cascada ON public.usuario_submodulos;
CREATE TRIGGER usuario_submodulos_cascada
  AFTER UPDATE OF activo ON public.usuario_submodulos
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.usuario_submodulos_cascada();

-- ============================================================
-- submodulos — dejar de ser delegable revoca lo delegado
-- ============================================================
CREATE OR REPLACE FUNCTION public.submodulos_deja_de_ser_delegable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.usuario_submodulos SET activo = false
  WHERE submodulo_id = NEW.id
    AND activo
    AND otorgada_por IS NOT NULL
    AND public.equipo_de(otorgada_por) IS NOT NULL;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submodulos_deja_de_ser_delegable() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS submodulos_deja_de_ser_delegable ON public.submodulos;
CREATE TRIGGER submodulos_deja_de_ser_delegable
  AFTER UPDATE OF delegable ON public.submodulos
  FOR EACH ROW
  WHEN (OLD.delegable AND NOT NEW.delegable)
  EXECUTE FUNCTION public.submodulos_deja_de_ser_delegable();

-- ============================================================
-- equipos_miembros — entrar y salir
-- ============================================================
CREATE OR REPLACE FUNCTION public.equipos_miembros_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND (NEW.equipo_id <> OLD.equipo_id OR NEW.usuario_id <> OLD.usuario_id) THEN
    RAISE EXCEPTION 'Para cambiar de equipo se desactiva la membresía y se crea otra' USING ERRCODE = 'US015';
  END IF;

  IF NEW.activo AND (TG_OP = 'INSERT' OR NOT OLD.activo) THEN
    IF NOT EXISTS (SELECT 1 FROM public.equipos WHERE id = NEW.equipo_id AND activo) THEN
      RAISE EXCEPTION 'El equipo no existe o está desactivado' USING ERRCODE = 'US011';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.submodulos s ON s.id = us.submodulo_id
      WHERE us.usuario_id = NEW.usuario_id AND us.activo AND s.codigo = 'usuarios_gestionar'
    ) THEN
      RAISE EXCEPTION 'Quien administra usuarios no puede ser miembro de un equipo' USING ERRCODE = 'US002';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.activo AND NOT NEW.activo THEN
    IF EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.submodulos s ON s.id = us.submodulo_id
      WHERE us.usuario_id = NEW.usuario_id AND us.activo AND s.codigo = 'usuarios_delegar'
    ) THEN
      RAISE EXCEPTION 'Para sacar al delegador hay que elegir un heredero' USING ERRCODE = 'US009';
    END IF;

    -- Lo que le dieron por delegación no viaja al equipo nuevo; lo del admin sí.
    UPDATE public.usuario_submodulos us SET activo = false
    WHERE us.usuario_id = NEW.usuario_id
      AND us.activo
      AND us.otorgada_por IN (
        SELECT usuario_id FROM public.equipos_miembros
        WHERE equipo_id = NEW.equipo_id AND activo
      );
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.equipos_miembros_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS equipos_miembros_validar ON public.equipos_miembros;
CREATE TRIGGER equipos_miembros_validar
  BEFORE INSERT OR UPDATE ON public.equipos_miembros
  FOR EACH ROW EXECUTE FUNCTION public.equipos_miembros_validar();

-- ============================================================
-- equipos — no se desactiva con miembros
-- ============================================================
CREATE OR REPLACE FUNCTION public.equipos_validar_desactivar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.equipos_miembros WHERE equipo_id = NEW.id AND activo
  ) THEN
    RAISE EXCEPTION 'Un equipo con miembros activos no se puede desactivar' USING ERRCODE = 'US010';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.equipos_validar_desactivar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS equipos_validar_desactivar ON public.equipos;
CREATE TRIGGER equipos_validar_desactivar
  BEFORE UPDATE OF activo ON public.equipos
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.equipos_validar_desactivar();

-- ============================================================
-- usuarios — desactivar al delegador pide heredero
-- ============================================================
CREATE OR REPLACE FUNCTION public.usuarios_validar_desactivar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.usuario_submodulos us
    JOIN public.submodulos s ON s.id = us.submodulo_id
    WHERE us.usuario_id = NEW.id AND us.activo AND s.codigo = 'usuarios_delegar'
  ) THEN
    RAISE EXCEPTION 'Para sacar al delegador hay que elegir un heredero' USING ERRCODE = 'US009';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.usuarios_validar_desactivar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS usuarios_validar_desactivar ON public.usuarios;
CREATE TRIGGER usuarios_validar_desactivar
  BEFORE UPDATE OF activo ON public.usuarios
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.usuarios_validar_desactivar();

-- ============================================================
-- asignar_submodulos — el admin fija el conjunto de un usuario
-- ============================================================
-- Reemplaza el "desactivar todo + upsert" de la action: con cascadas, apagar
-- un permiso del delegador aunque sea un instante se lo saca a su equipo. Acá
-- solo se apaga lo que sale y se prende lo que entra; lo que ya estaba activo
-- conserva su `otorgada_por`. Solo `service_role`: el admin pasa su id porque
-- ahí `auth.uid()` es NULL.
CREATE OR REPLACE FUNCTION public.asignar_submodulos(p_admin uuid, p_usuario uuid, p_submodulos uuid[])
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  UPDATE public.usuario_submodulos SET activo = false
  WHERE usuario_id = p_usuario AND activo AND submodulo_id <> ALL (p_submodulos);

  INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
  SELECT DISTINCT p_usuario, x, p_admin, true FROM unnest(p_submodulos) AS x
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
    SET activo = true, otorgada_por = EXCLUDED.otorgada_por
    WHERE NOT public.usuario_submodulos.activo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.asignar_submodulos(uuid, uuid, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.asignar_submodulos(uuid, uuid, uuid[]) TO service_role;

-- ============================================================
-- quitar_delegador — la salida, con o sin heredero
-- ============================================================
-- Deja al saliente sin `usuarios_delegar` ni su vista; recién después se lo
-- puede desactivar o sacar del equipo. `p_no_copiar`: lo que el admin
-- desmarcó de la copia, que se revoca en cascada del equipo.
CREATE OR REPLACE FUNCTION public.quitar_delegador(
  p_admin uuid,
  p_saliente uuid,
  p_heredero uuid,
  p_no_copiar uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_equipo uuid := public.equipo_de(p_saliente);
  v_delegar uuid;
  v_vista uuid;
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT id, vista_id INTO v_delegar, v_vista
  FROM public.submodulos WHERE codigo = 'usuarios_delegar' AND activo;

  IF v_equipo IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.usuario_submodulos
    WHERE usuario_id = p_saliente AND submodulo_id = v_delegar AND activo
  ) THEN
    RAISE EXCEPTION 'Ese usuario no es el delegador de un equipo' USING ERRCODE = 'US014';
  END IF;

  IF p_heredero IS NOT NULL THEN
    IF p_heredero = p_saliente
       OR public.equipo_de(p_heredero) IS DISTINCT FROM v_equipo
       OR NOT EXISTS (SELECT 1 FROM public.usuarios WHERE id = p_heredero AND activo) THEN
      RAISE EXCEPTION 'El heredero tiene que ser otro miembro activo del mismo equipo' USING ERRCODE = 'US012';
    END IF;
    IF v_delegar = ANY (p_no_copiar) OR v_vista = ANY (p_no_copiar) THEN
      RAISE EXCEPTION 'El heredero recibe siempre la delegación' USING ERRCODE = 'US013';
    END IF;

    -- Lo que el saliente le había delegado al heredero pasa a ser del admin.
    UPDATE public.usuario_submodulos SET otorgada_por = p_admin
    WHERE usuario_id = p_heredero AND otorgada_por = p_saliente AND activo;

    -- El heredero recibe una copia de los permisos del saliente.
    INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
    SELECT p_heredero, submodulo_id, p_admin, true
    FROM public.usuario_submodulos
    WHERE usuario_id = p_saliente AND activo AND submodulo_id <> ALL (p_no_copiar)
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
      SET activo = true, otorgada_por = EXCLUDED.otorgada_por
      WHERE NOT public.usuario_submodulos.activo;

    -- Lo que delegó el saliente pasa al heredero...
    UPDATE public.usuario_submodulos SET otorgada_por = p_heredero
    WHERE otorgada_por = p_saliente AND activo;

    -- ...salvo lo que el heredero no tiene: el techo sigue valiendo.
    UPDATE public.usuario_submodulos d SET activo = false
    WHERE d.otorgada_por = p_heredero
      AND d.activo
      AND NOT EXISTS (
        SELECT 1 FROM public.usuario_submodulos h
        WHERE h.usuario_id = p_heredero AND h.submodulo_id = d.submodulo_id AND h.activo
      );
  END IF;

  -- Sin heredero, la cascada revoca todo lo que delegó.
  UPDATE public.usuario_submodulos SET activo = false
  WHERE usuario_id = p_saliente AND submodulo_id IN (v_delegar, v_vista) AND activo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.quitar_delegador(uuid, uuid, uuid, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.quitar_delegador(uuid, uuid, uuid, uuid[]) TO service_role;

-- ============================================================
-- delegar_submodulos — el delegador fija lo que le da a un miembro
-- ============================================================
-- INVOKER: corre con la sesión del delegador y pasa por la RLS de abajo; el
-- techo lo ponen los triggers. Solo toca lo que otorgó él: lo que dio el admin
-- no se apaga aunque no venga en la lista, y si viene no cambia de dueño.
CREATE OR REPLACE FUNCTION public.delegar_submodulos(p_usuario uuid, p_submodulos uuid[])
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.usuario_submodulos SET activo = false
  WHERE usuario_id = p_usuario
    AND activo
    AND otorgada_por = (select auth.uid())
    AND submodulo_id <> ALL (p_submodulos);

  INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
  SELECT DISTINCT p_usuario, x, (select auth.uid()), true
  FROM unnest(p_submodulos) AS x
  WHERE NOT EXISTS (
    SELECT 1 FROM public.usuario_submodulos
    WHERE usuario_id = p_usuario AND submodulo_id = x AND activo
  )
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
    SET activo = true, otorgada_por = EXCLUDED.otorgada_por;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delegar_submodulos(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delegar_submodulos(uuid, uuid[]) TO authenticated;

-- ============================================================
-- RLS — el delegador escribe en su equipo, a su nombre
-- ============================================================
-- Una fila inactiva de su equipo la puede reactivar aunque la haya dado otro:
-- vuelve a nacer como suya. Una activa, solo si es suya.
DROP POLICY IF EXISTS usuario_submodulos_insert_delegador ON public.usuario_submodulos;
CREATE POLICY usuario_submodulos_insert_delegador ON public.usuario_submodulos FOR INSERT
  WITH CHECK (
    tiene_permiso('usuarios_delegar')
    AND otorgada_por = (select auth.uid())
    AND usuario_id IN (
      SELECT usuario_id FROM public.equipos_miembros
      WHERE activo AND equipo_id = mi_equipo()
    )
  );

DROP POLICY IF EXISTS usuario_submodulos_update_delegador ON public.usuario_submodulos;
CREATE POLICY usuario_submodulos_update_delegador ON public.usuario_submodulos FOR UPDATE
  USING (
    tiene_permiso('usuarios_delegar')
    AND (NOT activo OR otorgada_por = (select auth.uid()))
    AND usuario_id IN (
      SELECT usuario_id FROM public.equipos_miembros
      WHERE activo AND equipo_id = mi_equipo()
    )
  )
  WITH CHECK (
    tiene_permiso('usuarios_delegar')
    AND otorgada_por = (select auth.uid())
    AND usuario_id IN (
      SELECT usuario_id FROM public.equipos_miembros
      WHERE activo AND equipo_id = mi_equipo()
    )
  );

GRANT INSERT (usuario_id, submodulo_id, otorgada_por, activo) ON public.usuario_submodulos TO authenticated;
GRANT UPDATE (activo, otorgada_por) ON public.usuario_submodulos TO authenticated;
