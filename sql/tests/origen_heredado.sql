-- Verificación de sql/058 (lo que nace en un hilo hereda su link de origen).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que plantillas.sql: `authenticated` +
-- `request.jwt.claims` para actuar, `role = none` para contar sin RLS.
--
-- Volver a correrlo entero después de tocar sql/058.
--
-- Último resultado: 4/4.

DO $test$
DECLARE
  v_admin uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_link  text := '/obras/00000000-0000-4000-8000-000000000001';
  v_t1    uuid;
  v_hilo  uuid;
  v_t2    uuid;
  v_t3    uuid;
  v_t4    uuid;
  v_t0    uuid;
  v_h2    uuid;
  v_t5    uuid;
  v_pl    uuid;
  v_n     int;
  r       text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  v_t1 := crear_tarea('OH con link', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', 'obras', v_link, NULL);
  v_hilo := convertir_tarea_en_hilo(v_t1);
  v_t2 := crear_tarea('OH siguiente paso', NULL, v_hilo, NULL, v_t1, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  v_t3 := crear_tarea('OH en paralelo', NULL, v_hilo, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  v_t4 := crear_tarea('OH link propio', NULL, v_hilo, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', 'compras', '/compras/1', NULL);

  v_pl := guardar_plantilla(NULL, 'OH plantilla', NULL, 'privada', 'hilo', 'privado', '{}',
    '[]'::jsonb, '[{"titulo":"OH desde plantilla"}]'::jsonb);
  PERFORM usar_plantilla(v_pl, NULL, NULL, v_hilo);

  v_t0 := crear_tarea('OH sin link', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  v_h2 := convertir_tarea_en_hilo(v_t0);
  v_t5 := crear_tarea('OH en hilo sin link', NULL, v_h2, NULL, v_t0, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas
   WHERE id IN (v_t2, v_t3) AND origen_app = 'obras' AND origen_punto = v_link;
  r := r || E'\n01 el siguiente paso y la tarea en paralelo heredan el link de la tarea convertida: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas WHERE id = v_t4 AND origen_app = 'compras' AND origen_punto = '/compras/1';
  r := r || E'\n02 la que trae su propio link lo conserva: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas
   WHERE hilo_id = v_hilo AND titulo = 'OH desde plantilla' AND origen_app = 'obras' AND origen_punto = v_link;
  r := r || E'\n03 usar una plantilla en el hilo hereda el de la tarea más antigua, no el último: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas WHERE id = v_t5 AND origen_app IS NULL AND origen_punto IS NULL;
  r := r || E'\n04 en un hilo sin link no inventa uno: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
