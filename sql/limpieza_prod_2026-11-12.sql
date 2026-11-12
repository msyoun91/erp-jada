-- Limpieza única de PRODUCCIÓN (2026-11-12): todo lo cargado hasta acá era de prueba.
-- Queda: somosjada@gmail.com con sus permisos, submodulos, submodulo_reglas, entes,
-- presupuestos_configuracion, monedas_principal. Ver decisiones/global/infra.md.
-- Correr en el SQL Editor del proyecto ERP de producción (qbpudocgdvpeadcyyhfh). Hacer backup antes.

BEGIN;

TRUNCATE
  catalogo_bajas, catalogo_casos, catalogo_categorias, catalogo_colores, catalogo_condiciones,
  catalogo_costos, catalogo_insumos, catalogo_materiales, catalogo_opciones, catalogo_paquetes,
  catalogo_piezas, catalogo_porcentajes, catalogo_porcentajes_valores, catalogo_variables,
  catalogo_variables_valores, catalogo_variantes, catalogo_versiones, catalogo_versiones_colores,
  catalogo_versiones_historia,
  contactos_accesos, contactos_ediciones, contactos_empresa_equipos, contactos_empresas,
  contactos_persona_empresa, contactos_personas, contactos_vinculos, contactos_vinculos_guardados,
  equipos, equipos_miembros, eventos,
  monedas_consultas, monedas_tipos_cambio,
  obras, obras_comisiones, obras_participantes,
  presupuestos, presupuestos_autorizaciones, presupuestos_links, presupuestos_links_visitas,
  presupuestos_opcionales, presupuestos_recargos, presupuestos_renglones, presupuestos_secciones,
  presupuestos_versiones,
  tareas, tareas_ediciones, tareas_hilos, tareas_notas, tareas_plantillas, tareas_plantillas_pasos,
  tareas_vinculos,
  usuario_notificaciones, usuario_tutorial, usuario_widgets
RESTART IDENTITY;

DELETE FROM auth.users WHERE email <> 'somosjada@gmail.com';

DO $$
DECLARE
  t text;
  n bigint;
  fallas text[] := '{}';
BEGIN
  IF (SELECT count(*) FROM auth.users) <> 1 OR NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'somosjada@gmail.com') THEN
    fallas := fallas || 'auth.users'::text;
  END IF;
  IF (SELECT count(*) FROM usuarios) <> 1 THEN fallas := fallas || 'usuarios'::text; END IF;
  IF NOT EXISTS (SELECT 1 FROM usuario_submodulos) THEN fallas := fallas || 'usuario_submodulos vacía'::text; END IF;
  FOR t IN SELECT unnest(ARRAY['catalogo_insumos','contactos_personas','eventos','obras','presupuestos','tareas','usuario_notificaciones','equipos']) LOOP
    EXECUTE format('SELECT count(*) FROM %I', t) INTO n;
    IF n > 0 THEN fallas := fallas || (t || '=' || n); END IF;
  END LOOP;
  IF cardinality(fallas) > 0 THEN
    RAISE EXCEPTION 'Limpieza abortada: %', fallas;
  END IF;
END $$;

COMMIT;

-- Portal de producción (gprkjktlbtemzzjanijn), aparte:
-- TRUNCATE portal_links, portal_visitas;
