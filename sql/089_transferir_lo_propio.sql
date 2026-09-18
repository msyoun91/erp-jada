-- ============================================================
-- 089 — Transferir lo propio, sin ver lo ajeno
--
-- Pedido del usuario: "la función transferir obras, transferir empresas y
-- transferir personas pueden crearse 2 de cada? Uno personal y otro que puede
-- ver la lista de todos y hacer transferencia aunque sean ajenas".
--
-- **No son dos funciones: son dos submódulos sobre la misma función.** La regla
-- vive una sola vez (fuente única de verdad); lo que se duplica es la puerta,
-- que es lo que el sistema sabe repartir (autorización = submódulos).
--
-- La mitad global YA existe, y es la única que hay hoy:
--   · `obras_transferir`      — ve TODAS las obras + transfiere cualquiera
--   · `obras_personas_todas`  — ve la agenda entera + transfiere cualquiera
--   · `obras_empresas_todas`  — ídem empresas
--
-- Lo que falta es lo personal: hoy, para mover una obra MÍA hay que tener
-- `obras_transferir`, que me muestra las obras de todos. Ese es el agujero.
--
-- Los tres permisos globales quedan con su código intacto a propósito: están
-- incrustados como "ve todo" en ~15 policies y funciones (sql/027 556/618/778,
-- 035, 042, 047, 051, 086…). Renombrarlos para que el código nuevo fuera el
-- global obligaba a tocar la RLS entera para no cambiar nada. El código nuevo
-- es el personal, y la RLS no se toca: quien solo transfiere lo suyo ve lo
-- suyo, que ya es el default de MODEL A.
--
-- Única excepción, §4: `usuarios_select` listaba el destino posible solo a
-- `obras_transferir`. Sin eso el selector de destino sale vacío y la
-- transferencia personal no se puede ni tipear.
--
-- Migrar agenda (`obras_migrar`, sql/088) no lleva par personal: la pantalla es
-- sobre la agenda de OTRO por definición.
--
-- Ver decisiones/obras/visibilidad.md.
-- ============================================================
BEGIN;

-- ============================================================
-- 1. Los tres submódulos personales
--
-- `funcion` exige `vista_id`: cada uno cuelga de la vista donde está el botón.
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden, vista_id)
SELECT f.codigo, 'obras', 'funcion', f.nombre, f.orden,
       (SELECT id FROM submodulos WHERE codigo = f.vista AND activo)
FROM (VALUES
  ('obras_transferir_propias',          'Transferir mis obras',    7, 'obras_ver'),
  ('obras_personas_transferir_propias', 'Transferir mis personas', 5, 'obras_personas'),
  ('obras_empresas_transferir_propias', 'Transferir mis empresas', 5, 'obras_empresas')
) AS f(codigo, nombre, orden, vista)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

-- El label de los globales mentía por omisión desde que existe el par: la
-- pantalla de permisos es donde alguien elige entre los dos.
UPDATE submodulos SET nombre = 'Transferir cualquier obra'
  WHERE codigo = 'obras_transferir' AND activo;
UPDATE submodulos SET nombre = 'Ver y transferir todas las personas'
  WHERE codigo = 'obras_personas_todas' AND activo;
UPDATE submodulos SET nombre = 'Ver y transferir todas las empresas'
  WHERE codigo = 'obras_empresas_todas' AND activo;

-- ============================================================
-- 2. La regla, en un solo lugar
--
-- Recibe el id y busca el dueño ella misma: así el guard de cada función es una
-- línea y no hay que reordenar el cuerpo (en `obras_transferir_candidatos` el
-- permiso se chequea ANTES de leer el dueño).
--
-- INVOKER: la llaman las cuatro funciones de transferencia, que son DEFINER, y
-- adentro de ellas ve la fila sea de quien sea. Llamada desde afuera solo
-- podría confirmar lo que ya ves, y no se otorga EXECUTE igual.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_transferir(p_tipo text, p_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN
      tiene_permiso('obras_transferir')
      OR (tiene_permiso('obras_transferir_propias')
          AND EXISTS (SELECT 1 FROM obras
                       WHERE id = p_id AND activo AND responsable_id = auth.uid()))
    WHEN 'empresa' THEN
      tiene_permiso('obras_empresas_todas')
      OR (tiene_permiso('obras_empresas_transferir_propias')
          AND EXISTS (SELECT 1 FROM obras_empresas
                       WHERE id = p_id AND activo AND creado_por = auth.uid()))
    WHEN 'persona' THEN
      tiene_permiso('obras_personas_todas')
      OR (tiene_permiso('obras_personas_transferir_propias')
          AND EXISTS (SELECT 1 FROM obras_personas
                       WHERE id = p_id AND activo AND creado_por = auth.uid()))
    ELSE false
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_puede_transferir(text, uuid) FROM PUBLIC;

-- ============================================================
-- 3. El guard de las cuatro funciones
--
-- Se parchea la línea, no se repega el cuerpo. Las cuatro funciones suman ~450
-- líneas de sql/087 y el cambio es un identificador en cada guard: repegarlas
-- es cuatro oportunidades de revertir sin querer algo de 085/086/087, y un
-- diff que nadie lee. `pg_get_functiondef` devuelve el cuerpo VIVO, así que el
-- reemplazo se aplica sobre lo que realmente está corriendo.
--
-- El `RAISE` de abajo es lo que hace esto seguro: si el guard no aparece —
-- porque una migración posterior lo reescribió — la transacción entera aborta
-- en vez de dejar la función sin parchear y el permiso nuevo sin efecto.
--
-- El mensaje y el ERRCODE de cada excepción no cambian: siguen diciendo "sin
-- permiso para transferir X", que es cierto en los dos casos.
-- ============================================================
DO $patch$
DECLARE
  r       record;
  v_def   text;
  v_nuevo text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('obras_transferir(uuid,uuid,uuid[],uuid[])',
       'tiene_permiso\(''obras_transferir''\)',
       'obras_puede_transferir(''obra'', p_obra_id)'),
      ('obras_transferir_persona(uuid,uuid,boolean)',
       'tiene_permiso\(''obras_personas_todas''\)',
       'obras_puede_transferir(''persona'', p_persona_id)'),
      ('obras_transferir_empresa(uuid,uuid,uuid[],uuid[],boolean)',
       'tiene_permiso\(''obras_empresas_todas''\)',
       'obras_puede_transferir(''empresa'', p_empresa_id)'),
      ('obras_transferir_candidatos(text,uuid)',
       'tiene_permiso\(''obras_(transferir|personas_todas|empresas_todas)''\)',
       'obras_puede_transferir(p_tipo, p_id)')
    ) AS t(firma, patron, llamada)
  LOOP
    v_def   := pg_get_functiondef(r.firma::regprocedure);
    v_nuevo := regexp_replace(v_def, r.patron, r.llamada, 'g');

    IF v_nuevo = v_def THEN
      RAISE EXCEPTION 'El guard de % no coincide con el patrón esperado', r.firma;
    END IF;

    EXECUTE v_nuevo;
  END LOOP;
END;
$patch$;

-- ============================================================
-- 4. El selector de destino
--
-- `usuarios_select` es la lista de "a quién puedo transferir". Se suman los
-- tres personales. Se repega entera porque ALTER POLICY reemplaza el USING.
-- ============================================================
ALTER POLICY usuarios_select ON public.usuarios
  USING (
    id = (select auth.uid())
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('tareas_lista')
    OR tiene_permiso('tareas_proyectos')
    OR tiene_permiso('obras_transferir')
    OR tiene_permiso('obras_transferir_propias')
    OR tiene_permiso('obras_personas_transferir_propias')
    OR tiene_permiso('obras_empresas_transferir_propias')
  );

COMMIT;
