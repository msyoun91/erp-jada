-- ============================================================
-- 051 — El receptor de una obra compartida vincula sus propios contactos
--
-- Pedido del usuario, sobre *Compartir con checklist* (sql/047-050). Cinco
-- cosas, todas en la ficha de una obra que me compartieron:
--
--   1. BUSCADOR DE PERSONA AL VINCULAR — deja de ser el de identidad mínima
--      cross-owner. Ahora `VincularPersonaPanel` busca solo en mi agenda
--      (owner-scoped), igual que el de empresas ya hacía. Cambio en
--      `actions.ts` (`buscarPersonasParaVincular`), no acá — se anota para no
--      perderlo: contradice *MODEL A → búsqueda de identidad mínima*, que
--      superamos por pedido explícito.
--
--   2. PUEDO VINCULAR. `obras_obra_persona_insert` / `obras_obra_empresa_insert`
--      exigían `obras_es_mi_obra(obra_id)` — el responsable y nadie más. Ahora
--      el receptor de la obra compartida también inserta, PERO solo entidades
--      MÍAS (`creado_por = auth.uid()`). En mi propia obra, sin cambios.
--
--   3. VINCULAR NO ES COMPARTIR — PERO EL DUEÑO LO VE. Los vínculos tienen
--      ahora `creado_por`. El responsable de la obra (y el admin) ven TODOS los
--      vínculos, incluidos los que sumó un receptor. La entidad del receptor es
--      privada, así que el nombre lo resuelve `obras_vinculos_de_obra()`
--      (DEFINER, identidad mínima — nombre/razón social + roles, nunca contacto)
--      y la ficha marca "lo agregó <usuario>". Editar roles/observaciones sigue
--      siendo del que creó el vínculo; el responsable puede quitarlo pero no
--      reescribirlo (trigger `guard_edicion`, `OB028`).
--
--   4. EL RECEPTOR NO VE LO QUE NO SE LE COMPARTIÓ. El SELECT de los vínculos
--      deja de colgar de `obras_puede_ver_obra` (true entero para el receptor)
--      y pasa a "mío, del responsable, o compartido conmigo por checklist".
--      Para el receptor, el interior no compartido no se devuelve — ni la fila.
--      Reversa de sql/047 §"El receptor ve la obra y sus vínculos". Los
--      referentes (comisión) tampoco se le muestran.
--
--   5. AL REVOCAR, CASCADA. `obras_revocar_obra` desactiva también los vínculos
--      que el receptor agregó a esa obra (`creado_por = p_usuario_id`). El
--      panel avisa antes: `obras_contar_vinculos_receptor(obra, usuario)`.
--
-- Backfill: los vínculos existentes son todos del responsable de su obra
-- (antes de esto nadie más podía insertarlos). `creado_por` arranca ahí.
-- ============================================================

-- ============================================================
-- 1. `creado_por` en las dos tablas de vínculo
--
-- Lo pone un trigger BEFORE INSERT y no un WITH CHECK + columna del cliente:
-- así `obras_vincular_empresa` (sql/034, INVOKER) tampoco tiene que pasarlo, y
-- el cliente no lo puede falsear.
-- ============================================================
ALTER TABLE obras_obra_empresa ADD COLUMN IF NOT EXISTS creado_por uuid REFERENCES usuarios(id);
ALTER TABLE obras_obra_persona ADD COLUMN IF NOT EXISTS creado_por uuid REFERENCES usuarios(id);

UPDATE obras_obra_empresa v
  SET creado_por = o.responsable_id
  FROM obras o WHERE o.id = v.obra_id AND v.creado_por IS NULL;
UPDATE obras_obra_persona v
  SET creado_por = o.responsable_id
  FROM obras o WHERE o.id = v.obra_id AND v.creado_por IS NULL;

ALTER TABLE obras_obra_empresa ALTER COLUMN creado_por SET NOT NULL;
ALTER TABLE obras_obra_persona ALTER COLUMN creado_por SET NOT NULL;

-- DEFAULT además del trigger: el cliente no pasa `creado_por` en el .insert()
-- (queda opcional en database.types.ts). El trigger es la garantía de que no
-- se puede falsear aunque lo manden.
ALTER TABLE obras_obra_empresa ALTER COLUMN creado_por SET DEFAULT auth.uid();
ALTER TABLE obras_obra_persona ALTER COLUMN creado_por SET DEFAULT auth.uid();

CREATE OR REPLACE FUNCTION obras_vinculo_set_creado_por()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
BEGIN
  NEW.creado_por := auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_creado_por ON obras_obra_empresa;
CREATE TRIGGER set_creado_por BEFORE INSERT ON obras_obra_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_vinculo_set_creado_por();

DROP TRIGGER IF EXISTS set_creado_por ON obras_obra_persona;
CREATE TRIGGER set_creado_por BEFORE INSERT ON obras_obra_persona
  FOR EACH ROW EXECUTE FUNCTION obras_vinculo_set_creado_por();

-- El cliente no puede escribir `creado_por`: el `GRANT UPDATE` de sql/033 es
-- por columna y no la incluye, así que no hay privilegio que revocar. En un
-- INSERT lo pisa el trigger.

-- ============================================================
-- 2. Helpers: quién es receptor de qué
--
-- DEFINER + parámetro: `obras_obra_compartida` también tiene `obra_id`, y un
-- EXISTS inline en la policy con la columna sin calificar da el sombreado de
-- sql/047-048 (`c.obra_id = c.obra_id`, siempre true). Un parámetro no se
-- sombrea.
--
-- `_con(obra, usuario)` es la base; `_conmigo(obra)` la usa con `auth.uid()`.
-- `_con` la usa el trigger `guard_edicion`: "¿el que creó esta fila es hoy
-- receptor de la obra?" — si sí, y no es él quien edita, solo puede quitarla.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_obra_compartida_con(p_obra_id uuid, p_usuario_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_obra_compartida c
    WHERE c.obra_id = p_obra_id AND c.usuario_id = p_usuario_id AND c.activo
  );
$$;

CREATE OR REPLACE FUNCTION obras_obra_compartida_conmigo(p_obra_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT obras_obra_compartida_con(p_obra_id, auth.uid());
$$;

CREATE OR REPLACE FUNCTION obras_empresa_compartida_conmigo(p_empresa_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_empresa_compartida c
    WHERE c.empresa_id = p_empresa_id AND c.usuario_id = auth.uid() AND c.activo
  );
$$;

CREATE OR REPLACE FUNCTION obras_persona_compartida_conmigo(p_persona_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_compartida c
    WHERE c.persona_id = p_persona_id AND c.usuario_id = auth.uid() AND c.activo
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_obra_compartida_con(uuid, uuid)  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_obra_compartida_conmigo(uuid)    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_empresa_compartida_conmigo(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_persona_compartida_conmigo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_obra_compartida_con(uuid, uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_obra_compartida_conmigo(uuid)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_empresa_compartida_conmigo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_persona_compartida_conmigo(uuid) TO authenticated;

-- ============================================================
-- 3. Policies de vínculo — obra↔empresa
--
-- INSERT: mi obra (cualquier empresa visible, como hoy) o obra compartida
--         conmigo + empresa mía.
-- SELECT: el responsable y el admin ven TODO (incluido lo del receptor —
--         el nombre lo resuelve obras_vinculos_de_obra); el receptor ve lo
--         suyo + el interior que le tildaron.
-- UPDATE: el que lo creó, o el responsable de la obra (el trigger
--         guard_edicion limita al responsable a quitar, no reescribir, lo
--         que agregó un receptor).
-- ============================================================
DROP POLICY IF EXISTS obras_obra_empresa_insert ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_insert ON obras_obra_empresa FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_vincular')
    AND obras_puede_ver_empresa(empresa_id)
    AND (
      obras_es_mi_obra(obra_id)
      OR (
        obras_obra_compartida_conmigo(obra_id)
        AND EXISTS (
          SELECT 1 FROM obras_empresas e
          WHERE e.id = obras_obra_empresa.empresa_id AND e.creado_por = auth.uid()
        )
      )
    )
  );

DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa FOR SELECT
  USING (
    creado_por = auth.uid()
    OR obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (
      obras_obra_compartida_conmigo(obra_id)
      AND obras_empresa_compartida_conmigo(empresa_id)
    )
  );

DROP POLICY IF EXISTS obras_obra_empresa_update ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_update ON obras_obra_empresa FOR UPDATE
  USING (tiene_permiso('obras_vincular') AND (creado_por = auth.uid() OR obras_es_mi_obra(obra_id)))
  WITH CHECK (tiene_permiso('obras_vincular') AND (creado_por = auth.uid() OR obras_es_mi_obra(obra_id)));

-- ============================================================
-- 4. Policies de vínculo — obra↔persona (misma forma)
-- ============================================================
DROP POLICY IF EXISTS obras_obra_persona_insert ON obras_obra_persona;
CREATE POLICY obras_obra_persona_insert ON obras_obra_persona FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_vincular')
    AND obras_puede_ver_persona(persona_id)
    AND (
      obras_es_mi_obra(obra_id)
      OR (
        obras_obra_compartida_conmigo(obra_id)
        AND EXISTS (
          SELECT 1 FROM obras_personas p
          WHERE p.id = obras_obra_persona.persona_id AND p.creado_por = auth.uid()
        )
      )
    )
  );

DROP POLICY IF EXISTS obras_obra_persona_select ON obras_obra_persona;
CREATE POLICY obras_obra_persona_select ON obras_obra_persona FOR SELECT
  USING (
    creado_por = auth.uid()
    OR obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (
      obras_obra_compartida_conmigo(obra_id)
      AND obras_persona_compartida_conmigo(persona_id)
    )
  );

DROP POLICY IF EXISTS obras_obra_persona_update ON obras_obra_persona;
CREATE POLICY obras_obra_persona_update ON obras_obra_persona FOR UPDATE
  USING (tiene_permiso('obras_vincular') AND (creado_por = auth.uid() OR obras_es_mi_obra(obra_id)))
  WITH CHECK (tiene_permiso('obras_vincular') AND (creado_por = auth.uid() OR obras_es_mi_obra(obra_id)));

-- ============================================================
-- 4b. Editar un vínculo es de quien lo creó
--
-- La policy de UPDATE deja pasar al responsable (para que pueda QUITAR de la
-- obra lo que sumó un receptor, y para editar lo suyo y lo heredado de una
-- transferencia). El trigger acota: si la fila la creó alguien que hoy es
-- receptor de la obra y no es él quien edita, `roles` / `observaciones` /
-- `empresa_id` no se tocan — solo `activo`.
--
-- SECURITY INVOKER: no lee tablas directo (solo OLD/NEW + un helper DEFINER),
-- así queda fuera de la superficie RPC de anon (advisor 0028), igual que
-- `obras_vinculo_set_creado_por`.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_vinculo_guard_edicion()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS DISTINCT FROM OLD.creado_por
     AND obras_obra_compartida_con(OLD.obra_id, OLD.creado_por)
     AND (
       NEW.roles         IS DISTINCT FROM OLD.roles
       OR NEW.observaciones IS DISTINCT FROM OLD.observaciones
       OR NEW.empresa_id  IS DISTINCT FROM OLD.empresa_id
     )
  THEN
    RAISE EXCEPTION 'Ese vínculo lo agregó otro usuario: podés quitarlo de la obra, no editarlo'
      USING ERRCODE = 'OB028';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_edicion ON obras_obra_empresa;
CREATE TRIGGER guard_edicion BEFORE UPDATE ON obras_obra_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_vinculo_guard_edicion();

DROP TRIGGER IF EXISTS guard_edicion ON obras_obra_persona;
CREATE TRIGGER guard_edicion BEFORE UPDATE ON obras_obra_persona
  FOR EACH ROW EXECUTE FUNCTION obras_vinculo_guard_edicion();

REVOKE EXECUTE ON FUNCTION public.obras_vinculo_guard_edicion() FROM PUBLIC;

-- ============================================================
-- 5. Referentes — el receptor de una obra compartida no ve la comisión
--
-- sql/047 lo dejó pasar ("si molesta se acota; hoy no"). Ahora molesta: es
-- interior no compartido, y la comisión es el dato sensible de la ficha de
-- obra. Solo el responsable y el admin del módulo.
-- ============================================================
DROP POLICY IF EXISTS obras_obra_referente_select ON obras_obra_referente;
CREATE POLICY obras_obra_referente_select ON obras_obra_referente FOR SELECT
  USING (
    tiene_permiso('obras_referentes')
    AND (obras_es_mi_obra(obra_id) OR tiene_permiso('obras_transferir'))
  );

-- ============================================================
-- 6. Revocar la obra — arrastra los vínculos del receptor
--
-- Al desactivar filas de `obras_obra_persona`, el trigger `cascada_desactivar`
-- (sql/036) baja también sus referentes — el receptor no debería tener, pero
-- queda consistente.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_revocar_obra(p_obra_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras o WHERE o.id = p_obra_id AND o.responsable_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede revocar el acceso' USING ERRCODE = 'OB026';
  END IF;

  UPDATE obras_obra_compartida
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id AND activo;

  -- Lo que se compartió tildándolo en el checklist de esta obra cae con ella.
  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  UPDATE obras_persona_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  -- Vincular no es compartir: los vínculos que el receptor agregó a esta obra
  -- se caen cuando pierde el acceso.
  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;

  UPDATE obras_obra_persona
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;
END;
$$;

-- ============================================================
-- 7. Cuántos vínculos agregó un receptor — para el aviso antes de revocar
--
-- Un solo viaje, con gate propio (el responsable de la obra). El panel lo
-- llama al tocar la "X" de un usuario en "Compartida con".
-- ============================================================
CREATE OR REPLACE FUNCTION obras_contar_vinculos_receptor(p_obra_id uuid, p_usuario_id uuid)
RETURNS integer LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (
    (SELECT count(*) FROM public.obras_obra_empresa
     WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo)
    + (SELECT count(*) FROM public.obras_obra_persona
     WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo)
  )::integer
  WHERE EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_contar_vinculos_receptor(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_contar_vinculos_receptor(uuid, uuid) TO authenticated;

-- ============================================================
-- 8. obras_vinculos_de_obra — las dos listas de la ficha, con el nombre
--    resuelto y quién lo agregó
--
-- DEFINER como las de Auditoría: la empresa/persona que sumó un receptor es
-- privada, así que el embed de PostgREST la devolvería en NULL y la ficha del
-- responsable mostraría "—". Acá el JOIN resuelve el nombre igual —identidad
-- mínima, nunca contacto— y agrega `creado_por` + su nombre para el "lo
-- agregó <usuario>".
--
-- El WHERE por fila repite la lógica de la policy de SELECT (obligado: dentro
-- de una DEFINER no hay RLS). Un solo criterio, misma forma que
-- `obras_relaciones_compartibles_*`.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_vinculos_de_obra(p_obra_id uuid)
RETURNS TABLE (
  tipo              text,
  vinculo_id        uuid,
  entidad_id        uuid,
  nombre            text,
  detalle           text,
  roles             text[],
  observaciones     text,
  empresa_id        uuid,
  creado_por        uuid,
  creado_por_nombre text,
  es_de_receptor    boolean
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT obras_puede_ver_obra(p_obra_id) THEN
    RAISE EXCEPTION 'Sin acceso a esta obra' USING ERRCODE = 'OB022';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, oe.id, e.id, e.razon_social, NULL::text,
         oe.roles::text[], oe.observaciones, NULL::uuid,
         oe.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, oe.creado_por)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  JOIN usuarios u       ON u.id = oe.creado_por
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND (
      oe.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_empresa_compartida_conmigo(oe.empresa_id))
    )

  UNION ALL
  SELECT 'persona'::text, op.id, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         (SELECT e2.razon_social FROM obras_empresas e2 WHERE e2.id = op.empresa_id),
         op.roles::text[], op.observaciones, op.empresa_id,
         op.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, op.creado_por)
  FROM obras_obra_persona op
  JOIN obras_personas p  ON p.id = op.persona_id
  JOIN usuarios u        ON u.id = op.creado_por
  WHERE op.obra_id = p_obra_id AND op.activo
    AND (
      op.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_persona_compartida_conmigo(op.persona_id))
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_vinculos_de_obra(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_vinculos_de_obra(uuid) TO authenticated;
