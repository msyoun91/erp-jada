-- sql/114 — tareas: bajas y cambios de equipo.
--
-- La baja de un usuario y su salida de un equipo entregan sus hilos (todos,
-- abiertos y cerrados) y sus pasos abiertos al delegador del equipo de cada
-- fila: el `equipo_id` guardado, que es el equipo del que es el compromiso.
-- Sin delegador que pueda recibir, la fila queda con él: huérfana, la muestra
-- Todas. Entrar a un equipo desde independiente le pone ese equipo a lo
-- abierto suyo; lo cerrado queda sin equipo.
-- Perder `tareas_ver` no mueve nada. Los avisos llegan con su propia migración.
-- Decisiones: `decisiones/tareas/bajas.md`. Verificado con
-- `sql/tests/tareas_bajas.sql`.
--
-- Las escrituras corren a profundidad 2: las reglas de actor de `sql/113` no
-- aplican, y `tareas_al_editar` recalcula el equipo y deja de ser pedido lo
-- que ya no lo es. El delegador es del mismo equipo, así que mover el hilo no
-- dispara `tareas_hilos_transferir`. Nunca falla: la baja de un despedido va
-- en el acto.

CREATE OR REPLACE FUNCTION public.tareas_entregar(p_usuario uuid)
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
  UPDATE public.tareas_hilos h
  SET responsable_id = d.destino
  FROM (SELECT id, public.tareas_delegador_de(id) AS destino FROM public.equipos) d
  WHERE h.responsable_id = p_usuario
    AND d.id = h.equipo_id
    AND d.destino IS NOT NULL
    AND public.tareas_puede_recibir(d.destino, NULL);

  UPDATE public.tareas t
  SET asignado_id = d.destino
  FROM (SELECT id, public.tareas_delegador_de(id) AS destino FROM public.equipos) d
  WHERE t.asignado_id = p_usuario
    AND t.estado IN ('solicitada', 'pendiente', 'rechazada')
    AND d.id = t.equipo_id
    AND d.destino IS NOT NULL
    AND public.tareas_puede_recibir(d.destino, NULL);
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_entregar(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tareas_usuario_baja()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.tareas_entregar(NEW.id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.tareas_cambio_de_equipo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.activo AND NOT NEW.activo THEN
    PERFORM public.tareas_entregar(NEW.usuario_id);

  -- Lo abierto sin equipo es de cuando era independiente: lo que traía de otro
  -- equipo ya se entregó al salir, o quedó huérfano con ese equipo.
  ELSIF NEW.activo AND (TG_OP = 'INSERT' OR NOT OLD.activo) THEN
    UPDATE public.tareas_hilos SET equipo_id = NEW.equipo_id
    WHERE responsable_id = NEW.usuario_id AND equipo_id IS NULL AND estado = 'abierto';

    UPDATE public.tareas SET equipo_id = NEW.equipo_id
    WHERE asignado_id = NEW.usuario_id AND equipo_id IS NULL
      AND estado IN ('solicitada', 'pendiente', 'rechazada');
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_usuario_baja() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_cambio_de_equipo() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_usuario_baja ON public.usuarios;
CREATE TRIGGER tareas_usuario_baja
  AFTER UPDATE OF activo ON public.usuarios
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.tareas_usuario_baja();

DROP TRIGGER IF EXISTS tareas_cambio_de_equipo ON public.equipos_miembros;
CREATE TRIGGER tareas_cambio_de_equipo
  AFTER INSERT OR UPDATE OF activo ON public.equipos_miembros
  FOR EACH ROW EXECUTE FUNCTION public.tareas_cambio_de_equipo();
