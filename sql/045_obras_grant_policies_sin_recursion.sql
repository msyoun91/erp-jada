-- ============================================================
-- 045 — Fix: recursión infinita en la policy de obras_empresas
--
-- `sql/039` puso en `obras_empresas_select` un `EXISTS (SELECT … FROM
-- obras_empresa_compartida …)` inline, y la policy de esa tabla
-- (`empresa_compartida_select`) a su vez hacía `EXISTS (SELECT … FROM
-- obras_empresas …)`. Cualquier lectura de `obras_empresas` —incluido el
-- RETURNING de un INSERT— entra en bucle: 42P17.
--
-- (La rama de personas no recursaba —`obras_personas_select` llega a
-- `obras_persona_compartida` solo a través de `obras_puede_ver_persona`, que es
-- DEFINER y saltea RLS— pero se simplifica igual, por coherencia.)
--
-- Las tres policies de las tablas de grant se acotan a `usuario_id = auth.uid()`
-- (el receptor) y `otorgada_por = auth.uid()`. Quien otorgó es siempre el dueño
-- —`obras_compartir_*` lo exige—, así que la lista "compartida con" de la ficha
-- sigue saliendo completa sin tocar `obras_personas` / `obras_empresas`.
-- ============================================================
DROP POLICY IF EXISTS persona_compartida_select ON obras_persona_compartida;
CREATE POLICY persona_compartida_select ON obras_persona_compartida FOR SELECT
  USING (usuario_id = auth.uid() OR otorgada_por = auth.uid());

DROP POLICY IF EXISTS empresa_compartida_select ON obras_empresa_compartida;
CREATE POLICY empresa_compartida_select ON obras_empresa_compartida FOR SELECT
  USING (usuario_id = auth.uid() OR otorgada_por = auth.uid());

DROP POLICY IF EXISTS grant_ctx_select ON obras_persona_grant_contextual;
CREATE POLICY grant_ctx_select ON obras_persona_grant_contextual FOR SELECT
  USING (usuario_id = auth.uid() OR otorgada_por = auth.uid());
