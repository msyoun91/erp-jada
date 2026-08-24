-- Pasos de tarea + vista Misión.
--
-- Un "paso" es una tarea que no se puede empezar hasta que otra esté
-- completada. Es el eje ortogonal al hilo: el hilo AGRUPA tareas que corren en
-- paralelo, la cadena de pasos las ORDENA.
--
-- Decisiones que explican por qué esto es una columna y no una tabla nueva:
--
-- 1. Un solo previo. La regla de negocio es "se puede hacer si se cumple el
--    previo" — cadena lineal, no grafo de dependencias. `paso_anterior_id`
--    alcanza; una tabla `tareas_dependencias` sería un DAG genérico para un
--    problema que no existe.
--
-- 2. La cadena vive dentro de un hilo. `tareas_select` ya resuelve la
--    visibilidad en cascada del hilo (`puede_ver_hilo`), así que "ver los pasos
--    previos" no necesita ninguna regla de visibilidad nueva: si ves el hilo,
--    ves la cadena entera. Encadenar tareas sueltas obligaría a inventar una
--    función SECURITY DEFINER para devolver stubs de los pasos invisibles.
--
-- 3. `paso_anterior_id` es inmutable. Una fila nueva nunca puede ser ancestro
--    de otra, así que el grafo es siempre un bosque: no hace falta recorrer la
--    cadena buscando ciclos, ni en INSERT ni en UPDATE.
--
-- 4. "Bloqueada" no es un estado guardado. Se deriva de
--    `paso_anterior.estado <> 'completada'`. Meterlo en `estado_tarea` obligaría
--    a sincronizarlo en cada completar/cancelar/reabrir — la duplicación de
--    lógica que la regla prohíbe.
--
-- 5. Recurrencia y pasos no conviven (opción b). Una instancia recurrente se
--    genera al completar la anterior; un paso de una cadena no tiene una
--    "próxima instancia" que tenga sentido. Se prohíbe de los dos lados.

-- ============================================================
-- 1. tareas.paso_anterior_id
-- ============================================================
ALTER TABLE tareas
  ADD COLUMN IF NOT EXISTS paso_anterior_id uuid REFERENCES tareas(id);

-- Sin hilo no hay cascada de visibilidad, y sin cascada la cadena se ve a
-- pedazos (ver nota 2).
ALTER TABLE tareas DROP CONSTRAINT IF EXISTS tareas_paso_exige_hilo;
ALTER TABLE tareas ADD CONSTRAINT tareas_paso_exige_hilo
  CHECK (paso_anterior_id IS NULL OR hilo_id IS NOT NULL);

-- Lado "siguiente" de la nota 5. El lado "previo" necesita trigger, porque un
-- CHECK no puede mirar otra fila.
ALTER TABLE tareas DROP CONSTRAINT IF EXISTS tareas_paso_sin_recurrencia;
ALTER TABLE tareas ADD CONSTRAINT tareas_paso_sin_recurrencia
  CHECK (paso_anterior_id IS NULL OR recurrencia_cantidad IS NULL);

-- Un solo siguiente por paso: la cadena no bifurca. Parcial por `activo` para
-- que un paso desactivado deje libre su lugar.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_paso_anterior_activo
  ON tareas (paso_anterior_id) WHERE activo AND paso_anterior_id IS NOT NULL;

-- ============================================================
-- 2. validar_paso_tarea — armado de la cadena
-- ============================================================
-- SECURITY DEFINER a propósito: un guard que la RLS puede dejar ciego no es un
-- guard. Si el EXISTS del paso siguiente se filtrara por RLS, un usuario que no
-- ve al siguiente rompería la cadena sin que el trigger se entere.
CREATE OR REPLACE FUNCTION validar_paso_tarea()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_previo tareas%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.paso_anterior_id IS DISTINCT FROM OLD.paso_anterior_id THEN
      RAISE EXCEPTION 'El paso previo de una tarea no se puede cambiar'
        USING ERRCODE = 'TA005';
    END IF;

    IF NEW.hilo_id IS DISTINCT FROM OLD.hilo_id
       AND (
         NEW.paso_anterior_id IS NOT NULL
         OR EXISTS (SELECT 1 FROM tareas s WHERE s.paso_anterior_id = NEW.id AND s.activo)
       ) THEN
      RAISE EXCEPTION 'No se puede mover de hilo una tarea encadenada'
        USING ERRCODE = 'TA006';
    END IF;

    IF NEW.recurrencia_cantidad IS NOT NULL
       AND EXISTS (SELECT 1 FROM tareas s WHERE s.paso_anterior_id = NEW.id AND s.activo) THEN
      RAISE EXCEPTION 'Una tarea con paso siguiente no puede ser recurrente'
        USING ERRCODE = 'TA005';
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.paso_anterior_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.paso_anterior_id = NEW.id THEN
    RAISE EXCEPTION 'Una tarea no puede ser su propio paso previo'
      USING ERRCODE = 'TA005';
  END IF;

  SELECT * INTO v_previo FROM tareas WHERE id = NEW.paso_anterior_id;

  IF NOT FOUND OR NOT v_previo.activo THEN
    RAISE EXCEPTION 'El paso previo no existe o está desactivado'
      USING ERRCODE = 'TA005';
  END IF;

  IF v_previo.hilo_id IS DISTINCT FROM NEW.hilo_id THEN
    RAISE EXCEPTION 'El paso previo tiene que estar en el mismo hilo'
      USING ERRCODE = 'TA005';
  END IF;

  IF v_previo.recurrencia_cantidad IS NOT NULL THEN
    RAISE EXCEPTION 'Una tarea recurrente no puede tener paso siguiente'
      USING ERRCODE = 'TA005';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validar_paso_tarea() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_paso_tarea ON tareas;
CREATE TRIGGER trg_validar_paso_tarea
  BEFORE INSERT OR UPDATE OF paso_anterior_id, hilo_id, recurrencia_cantidad ON tareas
  FOR EACH ROW
  EXECUTE FUNCTION validar_paso_tarea();

-- ============================================================
-- 3. validar_paso_previo — el bloqueo
-- ============================================================
-- Esta es la barrera de servidor: la UI grisea el botón, el trigger autoriza.
--
-- `cancelada` queda fuera de la lista a propósito. Si un paso se cancela, la
-- cadena queda trabada para siempre — cancelar los pasos que siguen tiene que
-- seguir siendo posible, o el hilo no se puede cerrar nunca.
CREATE OR REPLACE FUNCTION validar_paso_previo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado estado_tarea;
BEGIN
  IF NEW.paso_anterior_id IS NULL OR NEW.estado NOT IN ('en_progreso', 'completada') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
    RETURN NEW;
  END IF;

  SELECT estado INTO v_estado FROM tareas WHERE id = NEW.paso_anterior_id;

  IF v_estado <> 'completada' THEN
    RAISE EXCEPTION 'El paso previo todavía no está completado'
      USING ERRCODE = 'TA004';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validar_paso_previo() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_paso_previo ON tareas;
CREATE TRIGGER trg_validar_paso_previo
  BEFORE INSERT OR UPDATE OF estado ON tareas
  FOR EACH ROW
  EXECUTE FUNCTION validar_paso_previo();

-- ============================================================
-- 4. validar_desactivar_paso — no dejar la cadena huérfana
-- ============================================================
-- Desactivar un paso del medio deja al siguiente apuntando a una tarea que no
-- se ve y que nunca se va a completar: bloqueado para siempre. Se bloquea, no
-- se relinkea en silencio (mismo criterio que validar_quitar_miembro).
--
-- Va AFTER y no BEFORE: un BEFORE por fila vería a los siguientes todavía
-- activos según el orden en que le toquen las filas, y desactivar una cadena
-- entera en un solo UPDATE (`deshacerConversionHilo` usa `.in(...)`) fallaría
-- de forma intermitente. Los AFTER ROW se encolan y corren recién al final de
-- la sentencia, con todas las filas ya actualizadas.
--
-- CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED suma lo que el AFTER solo no
-- da: desmantelar una cadena en varias sentencias dentro de una misma
-- transacción. Hoy no hay ningún caller que lo haga (cada llamada de Supabase
-- es su propia transacción), pero el guard deja de depender de que el borrado
-- siga siendo una sola sentencia.
CREATE OR REPLACE FUNCTION validar_desactivar_paso()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM tareas s WHERE s.paso_anterior_id = NEW.id AND s.activo) THEN
    RAISE EXCEPTION 'Ese paso tiene un paso siguiente activo — desactivá la cadena desde el final'
      USING ERRCODE = 'TA007';
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validar_desactivar_paso() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_desactivar_paso ON tareas;
CREATE CONSTRAINT TRIGGER trg_validar_desactivar_paso
  AFTER UPDATE ON tareas
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION validar_desactivar_paso();

-- ============================================================
-- 5. Submódulo-vista Misión
-- ============================================================
-- Sin función propia: "crear siguiente paso" es crear una tarea, y crear tareas
-- ya lo gatea `tareas_lista`. Una función nueva sería un permiso más fino sin
-- necesidad demostrada.
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES ('tareas_mision', 'tareas', 'vista', 'Misión', 5)
ON CONFLICT DO NOTHING;

-- Misión no muestra nada que la Lista no muestre ya: es la misma información,
-- de a una y ordenada por temperatura. Quien tiene la Lista la recibe.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT us.usuario_id, nueva.id
FROM usuario_submodulos us
JOIN submodulos l ON l.id = us.submodulo_id AND l.codigo = 'tareas_lista'
CROSS JOIN submodulos nueva
WHERE us.activo AND nueva.codigo = 'tareas_mision'
ON CONFLICT DO NOTHING;
