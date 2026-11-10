-- Presupuestos, tramo 4: aprobar, rechazar con motivo y revertir con causa, y la obra que sigue a sus presupuestos.
-- Ficha y decisiones: decisiones/presupuestos.md (→ Estados y versiones, Efectos en la obra, La base). Esquema:
-- db_schema/presupuestos.md.
-- Errores, clase PR (siguen a sql/190): PR021 solo se aprueba una versión publicada · PR022 rechazar pide motivo (y detalle, con
-- "otro") · PR023 solo se revierte lo aprobado o rechazado · PR024 revertir pide la causa · PR025 la obra tiene un presupuesto
-- aprobado · PR026 la obra tiene presupuestos publicados.

-- ============================================================
-- 1. Lo que guarda el presupuesto
-- ============================================================
-- Cuál versión se eligió, por qué se rechazó y la nota del último cambio de estado: el detalle del rechazo o la causa de la
-- reversión. Sin GRANT: las escriben las funciones de abajo.
ALTER TABLE public.presupuestos
  ADD COLUMN IF NOT EXISTS version_aprobada_id uuid REFERENCES public.presupuestos_versiones (id),
  ADD COLUMN IF NOT EXISTS motivo_rechazo public.motivo_perdida,
  ADD COLUMN IF NOT EXISTS estado_nota text;

ALTER TABLE public.presupuestos DROP CONSTRAINT IF EXISTS presupuestos_aprobada;
ALTER TABLE public.presupuestos ADD CONSTRAINT presupuestos_aprobada
  CHECK ((estado::text = 'aprobado') = (version_aprobada_id IS NOT NULL));
ALTER TABLE public.presupuestos DROP CONSTRAINT IF EXISTS presupuestos_rechazo;
ALTER TABLE public.presupuestos ADD CONSTRAINT presupuestos_rechazo
  CHECK ((estado::text = 'rechazado') = (motivo_rechazo IS NOT NULL));
ALTER TABLE public.presupuestos DROP CONSTRAINT IF EXISTS presupuestos_estado_nota;
ALTER TABLE public.presupuestos ADD CONSTRAINT presupuestos_estado_nota
  CHECK (char_length(estado_nota) BETWEEN 1 AND 500 AND estado_nota = btrim(estado_nota));

CREATE INDEX IF NOT EXISTS presupuestos_version_aprobada_idx ON public.presupuestos (version_aprobada_id)
  WHERE version_aprobada_id IS NOT NULL;

-- El evento `estado` lleva el motivo y la nota en `detalle`, como el de la obra.
DROP TRIGGER IF EXISTS emitir_eventos ON public.presupuestos;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON public.presupuestos
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('presupuesto', '', 'motivo_rechazo,estado_nota');

-- ============================================================
-- 2. La obra sigue a sus presupuestos (decisiones/presupuestos.md → Efectos en la obra)
-- ============================================================
-- Con alguno aprobado, contratada; si no, con alguno publicado, en cotización; si no, y fue un rechazo, perdida con su motivo.
-- Una contratada a mano, sin aprobado, solo se mueve al aprobar. Congelada, la obra no cambia: frena lo que la movería.
-- Corre a profundidad 2, así que obras_al_editar no pide que quien actúa trabaje la obra: ya lo pidió la función que llama.
CREATE OR REPLACE FUNCTION public.presupuestos_mover_obra()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_o public.obras;
  v_nuevo public.estado_obra;
BEGIN
  SELECT * INTO v_o FROM public.obras WHERE id = NEW.obra_id FOR UPDATE;

  v_nuevo := CASE
    WHEN EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = v_o.id AND p.activo AND p.estado = 'aprobado')
      THEN 'contratada'
    WHEN v_o.estado = 'contratada' AND OLD.estado <> 'aprobado' THEN v_o.estado
    WHEN EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = v_o.id AND p.activo AND p.estado = 'publicado')
      THEN 'en_cotizacion'
    WHEN NEW.estado = 'rechazado' THEN 'perdida'
    ELSE v_o.estado
  END;

  IF v_nuevo = v_o.estado THEN
    RETURN NULL;
  END IF;
  IF v_o.congelada THEN
    RAISE EXCEPTION 'La obra espera aprobación: no cambia de estado ni se transfiere' USING ERRCODE = 'OB018';
  END IF;

  UPDATE public.obras
  SET estado = v_nuevo,
      motivo_perdida = CASE WHEN v_nuevo = 'perdida' THEN NEW.motivo_rechazo END,
      estado_nota = CASE WHEN v_nuevo = 'perdida' OR v_o.estado = 'contratada' THEN NEW.estado_nota END
  WHERE id = v_o.id;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_mover_obra() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_mover_obra ON public.presupuestos;
CREATE TRIGGER presupuestos_mover_obra
  AFTER UPDATE OF estado ON public.presupuestos
  FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
  EXECUTE FUNCTION public.presupuestos_mover_obra();

-- A mano: con un presupuesto aprobado la obra no sale de contratada (se revierte la aprobación), y con publicados no pasa a
-- perdida (primero se resuelven). DEFINER: cuenta también los presupuestos que quien edita no ve.
CREATE OR REPLACE FUNCTION public.presupuestos_obra_estado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.estado = 'contratada' AND NEW.estado <> 'contratada'
     AND EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = NEW.id AND p.activo AND p.estado = 'aprobado') THEN
    RAISE EXCEPTION 'La obra tiene un presupuesto aprobado: se revierte la aprobación' USING ERRCODE = 'PR025';
  END IF;
  IF NEW.estado = 'perdida' AND OLD.estado <> 'perdida'
     AND EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = NEW.id AND p.activo AND p.estado = 'publicado') THEN
    RAISE EXCEPTION 'La obra tiene presupuestos publicados: primero se aprueban o se rechazan' USING ERRCODE = 'PR026';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_obra_estado() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_obra_estado ON public.obras;
CREATE TRIGGER presupuestos_obra_estado
  BEFORE UPDATE OF estado ON public.obras
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_obra_estado();

-- ============================================================
-- 3. Aprobar, rechazar y revertir
-- ============================================================
-- Al aprobar o rechazar, lo abierto se descarta: lo que estaba en revisión vuelve a borrador (sus pedidos quedan retirados) y
-- los borradores quedan `activo = false`. Sin GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_cerrar_abiertas(p_presupuesto uuid)
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
  SELECT public.presupuestos_version_a_borrador(v.id)
  FROM public.presupuestos_versiones v
  WHERE v.presupuesto_id = p_presupuesto AND v.activo AND v.estado = 'en_revision';
  UPDATE public.presupuestos_versiones SET activo = false
  WHERE presupuesto_id = p_presupuesto AND activo AND estado = 'borrador';
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_cerrar_abiertas(uuid) FROM PUBLIC, anon, authenticated;

-- Aprueba el presupuesto con la variante elegida: las demás publicadas quedan inhabilitadas, que se calcula al mostrar.
-- DEFINER: el estado no tiene GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_aprobar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_p public.presupuestos;
BEGIN
  SELECT p.* INTO v_p
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version
  FOR UPDATE OF p;
  IF NOT FOUND OR NOT public.presupuestos_arma(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_v FROM public.presupuestos_versiones WHERE id = p_version FOR UPDATE;

  IF NOT v_p.activo OR v_p.estado <> 'publicado' THEN
    RAISE EXCEPTION 'El presupuesto % no admite aprobar: está %', v_p.codigo,
      CASE WHEN NOT v_p.activo THEN 'desactivado' ELSE v_p.estado::text END USING ERRCODE = 'PR003';
  END IF;
  IF NOT v_v.activo OR v_v.estado <> 'publicado' THEN
    RAISE EXCEPTION 'Solo se aprueba una versión publicada' USING ERRCODE = 'PR021';
  END IF;

  PERFORM public.presupuestos_cerrar_abiertas(v_p.id);
  UPDATE public.presupuestos SET estado = 'aprobado', version_aprobada_id = p_version, estado_nota = NULL WHERE id = v_p.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_aprobar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_aprobar(uuid) TO authenticated;

-- Rechaza el presupuesto entero, con el motivo de la lista de Obras; con "otro", el detalle.
CREATE OR REPLACE FUNCTION public.presupuestos_rechazar(p_presupuesto uuid, p_motivo public.motivo_perdida, p_detalle text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p public.presupuestos;
  v_detalle text := nullif(btrim(p_detalle), '');
BEGIN
  SELECT * INTO v_p FROM public.presupuestos WHERE id = p_presupuesto FOR UPDATE;
  IF NOT FOUND OR NOT public.presupuestos_arma(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
  END IF;

  IF NOT v_p.activo OR v_p.estado <> 'publicado' THEN
    RAISE EXCEPTION 'El presupuesto % no admite rechazar: está %', v_p.codigo,
      CASE WHEN NOT v_p.activo THEN 'desactivado' ELSE v_p.estado::text END USING ERRCODE = 'PR003';
  END IF;
  IF p_motivo IS NULL THEN
    RAISE EXCEPTION 'Rechazar un presupuesto pide el motivo' USING ERRCODE = 'PR022';
  END IF;
  IF p_motivo = 'otro' AND v_detalle IS NULL THEN
    RAISE EXCEPTION 'Con motivo "otro", contá qué pasó' USING ERRCODE = 'PR022';
  END IF;

  PERFORM public.presupuestos_cerrar_abiertas(v_p.id);
  UPDATE public.presupuestos SET estado = 'rechazado', motivo_rechazo = p_motivo, estado_nota = v_detalle WHERE id = v_p.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_rechazar(uuid, public.motivo_perdida, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_rechazar(uuid, public.motivo_perdida, text) TO authenticated;

-- Deshace una aprobación o un rechazo: vuelve a publicado, con la causa. Revierte quien autoriza lo del jefe en esa obra.
CREATE OR REPLACE FUNCTION public.presupuestos_revertir(p_presupuesto uuid, p_causa text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p public.presupuestos;
  v_causa text := nullif(btrim(p_causa), '');
BEGIN
  SELECT * INTO v_p FROM public.presupuestos WHERE id = p_presupuesto FOR UPDATE;
  IF NOT FOUND OR NOT public.presupuestos_ve(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
  END IF;
  IF NOT public.presupuestos_puede_autorizar('comercial', v_p.obra_id) THEN
    RAISE EXCEPTION 'Revierte quien autoriza: el jefe de la obra o gerencia' USING ERRCODE = '42501';
  END IF;

  IF v_p.estado NOT IN ('aprobado', 'rechazado') THEN
    RAISE EXCEPTION 'Solo se revierte un presupuesto aprobado o rechazado' USING ERRCODE = 'PR023';
  END IF;
  IF v_causa IS NULL THEN
    RAISE EXCEPTION 'Revertir pide la causa' USING ERRCODE = 'PR024';
  END IF;

  UPDATE public.presupuestos
  SET estado = 'publicado', version_aprobada_id = NULL, motivo_rechazo = NULL, estado_nota = v_causa
  WHERE id = v_p.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_revertir(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_revertir(uuid, text) TO authenticated;
