-- sql/097 — el dueño del contacto lo ve en la obra que le comparten
--
-- A transfiere su obra a B dejando un contacto suyo ("No se va"): el contacto
-- sigue en la agenda de A y el vínculo con la obra pasa a B (sql/095). Si B
-- después le comparte la obra a A, A la abre vacía: la rama de receptor de las
-- policies SELECT de vínculo y de `obras_vinculos_de_obra` solo conoce "lo
-- vinculé yo" y "me lo tildaron", y ninguna de las dos es su caso. Tampoco hay
-- salida por la UI: el checklist de B solo ofrece contactos de B.
--
-- La rama de receptor suma "el contacto es mío". No abre nada nuevo: ese
-- contacto ya lo ve en su agenda y la obra ya se la compartieron; faltaba la
-- fila que los une. Lectura sola — UPDATE no cambia, así que no edita ni quita
-- el vínculo, que es de quien lo cargó. Y dura lo que dure el compartir, como
-- las otras dos ramas.
--
-- El EXISTS califica la columna (`obras_obra_persona.persona_id`) por el
-- sombreado que mordió en sql/047-048; es la misma forma que ya tiene la rama
-- de receptor del INSERT.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · Policies SELECT de vínculo
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS obras_obra_persona_select ON obras_obra_persona;
CREATE POLICY obras_obra_persona_select ON obras_obra_persona
  FOR SELECT USING (
    obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (obras_obra_compartida_conmigo(obra_id)
        AND (creado_por = (select auth.uid())
             OR obras_ctx_vigente('persona', persona_id, 'obra', obra_id)
             OR EXISTS (SELECT 1 FROM obras_personas p
                        WHERE p.id = obras_obra_persona.persona_id
                          AND p.creado_por = (select auth.uid()))))
  );

DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa
  FOR SELECT USING (
    obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (obras_obra_compartida_conmigo(obra_id)
        AND (creado_por = (select auth.uid())
             OR obras_ctx_vigente('empresa', empresa_id, 'obra', obra_id)
             OR EXISTS (SELECT 1 FROM obras_empresas e
                        WHERE e.id = obras_obra_empresa.empresa_id
                          AND e.creado_por = (select auth.uid()))))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · obras_vinculos_de_obra — la misma rama
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_vinculos_de_obra(p_obra_id uuid)
RETURNS TABLE(tipo text, vinculo_id uuid, entidad_id uuid, nombre text, detalle text,
              roles text[], observaciones text, empresa_id uuid, creado_por uuid,
              creado_por_nombre text, es_de_receptor boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
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
          AND (e.creado_por = auth.uid()
               OR obras_ctx_vigente('empresa', oe.empresa_id, 'obra', p_obra_id)))
    )

  UNION ALL
  SELECT 'persona'::text, op.id, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         CASE WHEN vis.empresa_visible THEN e2.razon_social END,
         op.roles::text[], op.observaciones, op.empresa_id,
         op.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, op.creado_por)
  FROM obras_obra_persona op
  JOIN obras_personas p       ON p.id = op.persona_id
  JOIN usuarios u             ON u.id = op.creado_por
  LEFT JOIN obras_empresas e2 ON e2.id = op.empresa_id
  CROSS JOIN LATERAL (
    SELECT op.empresa_id IS NOT NULL
       AND (obras_es_mi_obra(p_obra_id)
            OR tiene_permiso('obras_transferir')
            OR obras_puede_ver_empresa(op.empresa_id)
            OR obras_ctx_vigente('empresa', op.empresa_id, 'obra', p_obra_id)) AS empresa_visible
  ) vis
  WHERE op.obra_id = p_obra_id AND op.activo
    AND (
      op.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND (p.creado_por = auth.uid()
               OR obras_ctx_vigente('persona', op.persona_id, 'obra', p_obra_id)))
    );
END;
$$;
