-- ============================================================
-- 036 — El referente se cae con el vínculo
--
-- `desvincularPersona` desactivaba la fila de `obras_obra_persona` y nada más.
-- La de `obras_obra_referente` quedaba `activo = true` y `getReferentes` la
-- seguía leyendo sin pasar por el vínculo. No se veía —la fila de la persona
-- desaparece de la ficha y el badge se va con ella— pero el dato quedaba: al
-- volver a vincular a la misma persona reaparecía la comisión vieja sin que
-- nadie la hubiera vuelto a cargar, y mientras tanto era un referente que la
-- UI no podía quitar, porque `ReferentePanel` solo lista personas vinculadas.
--
-- Es una invariante de datos, no de UI: va en la base y no en `actions.ts`.
--
-- Entra como tercera rama de `obras_cascada_desactivar` en vez de una función
-- nueva: esa función ya es el único lugar del módulo donde vive "qué se cae
-- cuando algo se cae", y el trigger es el mismo de siempre —`AFTER UPDATE`
-- con `WHEN (OLD.activo AND NOT NEW.activo)`—.
--
-- El `ELSE` implícito pasa a rama explícita por tabla: con tres tablas
-- colgando del mismo trigger, "todo lo que no es empresas es personas" deja
-- de ser verdad.
--
-- Sigue `SECURITY DEFINER` y ahora eso importa: la policy de UPDATE de
-- `obras_obra_referente` exige `obras_referentes`, que quien desvincula puede
-- no tener. Como INVOKER la cascada no vería la fila —RLS filtra, no falla— y
-- la invariante quedaría a merced del permiso de quien pasó por la pantalla.
--
-- Sin backfill: hoy no hay ninguna huérfana (4 referentes activos, 0 sin
-- vínculo activo).
--
-- Verificación: `sql/tests/obras_036.sql`.
-- ============================================================

CREATE OR REPLACE FUNCTION obras_cascada_desactivar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'obras_empresas' THEN
    UPDATE obras_persona_empresa SET activo = false
    WHERE empresa_id = OLD.id AND activo;

  ELSIF TG_TABLE_NAME = 'obras_personas' THEN
    UPDATE obras_persona_empresa SET activo = false
    WHERE persona_id = OLD.id AND activo;

  ELSIF TG_TABLE_NAME = 'obras_obra_persona' THEN
    UPDATE obras_obra_referente SET activo = false
    WHERE obra_id = OLD.obra_id AND persona_id = OLD.persona_id AND activo;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS cascada_desactivar ON obras_obra_persona;

CREATE TRIGGER cascada_desactivar
  AFTER UPDATE ON obras_obra_persona
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_cascada_desactivar();
