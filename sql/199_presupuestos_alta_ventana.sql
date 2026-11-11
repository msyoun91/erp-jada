-- "Llevar a un presupuesto" desde la calculadora de venta (decisiones/presupuestos.md → Pantallas): el alta suma una ventana
-- opcional (paquete, lo cargado y los opcionales) que se guarda junto con el presupuesto, su v1 y la sección. Si la ventana
-- falla (PR010), no queda un borrador vacío. Precio, líneas y mínimos los ponen los triggers de renglones, como al sumarla
-- desde el editor; cantidad 1, sin designación ni ubicación.
-- La firma cambia: se borra la de cinco parámetros, porque con los nuevos opcionales una llamada con cuatro o cinco sería
-- ambigua entre las dos.
-- Test: sql/tests/presupuestos_opcionales.sql (04).

DROP FUNCTION public.presupuestos_alta(uuid, text, public.moneda, numeric, text);

CREATE FUNCTION public.presupuestos_alta(p_obra uuid, p_nombre text, p_moneda public.moneda, p_alicuota numeric,
                                         p_seccion text DEFAULT 'General', p_paquete uuid DEFAULT NULL,
                                         p_entrada jsonb DEFAULT NULL, p_opcionales uuid[] DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_version uuid := gen_random_uuid();
  v_seccion uuid := gen_random_uuid();
BEGIN
  IF NOT public.presupuestos_arma(p_obra) THEN
    RAISE EXCEPTION 'No armás presupuestos en esta obra' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.presupuestos (id, nombre, obra_id) VALUES (v_id, btrim(p_nombre), p_obra);
  INSERT INTO public.presupuestos_versiones (id, presupuesto_id, variante) VALUES (v_version, v_id, 1);
  INSERT INTO public.presupuestos_secciones (id, version_id, nombre, moneda, alicuota)
  VALUES (v_seccion, v_version, btrim(p_seccion), p_moneda, p_alicuota);
  IF p_paquete IS NOT NULL THEN
    INSERT INTO public.presupuestos_renglones (version_id, seccion_id, tipo, paquete_id, entrada, opcionales)
    VALUES (v_version, v_seccion, 'catalogo', p_paquete, p_entrada, p_opcionales);
  END IF;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_alta(uuid, text, public.moneda, numeric, text, uuid, jsonb, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_alta(uuid, text, public.moneda, numeric, text, uuid, jsonb, uuid[]) TO authenticated;
