-- Verificación de sql/154: `{@accion|texto}` vale solo en la descripción de un
-- paso con "se completa cuando", bien cerrada, y `tareas_plantilla_texto` la
-- deja tal cual. Solo lecturas: corre en un DO que termina en RAISE.

DO $$
DECLARE
  v_obra uuid := (SELECT id FROM public.obras LIMIT 1);
  v_usuario uuid := (SELECT id FROM public.usuarios LIMIT 1);
  v_casos text[][] := ARRAY[
    -- caso, esperado, obtenido
    ['con condición de rol', 'true',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', 'Arquitecto',
       'Llamá y {@accion|vinculá al arquitecto} antes del viernes')::text],
    ['con condición de estado', 'true',
     public.tareas_plantillas_paso_vale('obra', NULL, 'estado', 'en_cotizacion', 'Cotizar',
       '{@accion|pasala a cotización}')::text],
    ['sin condición', 'false',
     public.tareas_plantillas_paso_vale('obra', NULL, NULL, NULL, 'Arquitecto',
       'Llamá y {@accion|vinculá al arquitecto}')::text],
    ['en el título', 'false',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', '{@accion|Vincular}', NULL)::text],
    ['sin cerrar', 'false',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', 'Arquitecto',
       'Llamá y {@accion|vinculá al arquitecto')::text],
    ['texto vacío', 'false',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', 'Arquitecto', '{@accion|}')::text],
    ['con otra marca adentro', 'false',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', 'Arquitecto',
       '{@accion|vinculá a {nombre}}')::text],
    ['dos veces', 'true',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', 'Arquitecto',
       '{@accion|vinculá} o {@accion|vinculá acá}')::text],
    ['sin marca, sin condición', 'true',
     public.tareas_plantillas_paso_vale('obra', NULL, NULL, NULL, 'Arquitecto', 'Llamá a {@arquitecto}')::text],
    ['junto a otras marcas', 'true',
     public.tareas_plantillas_paso_vale('obra', NULL, 'relacion_alta', 'arquitecto', 'Arquitecto',
       '{si no hay arquitecto}{@accion|Vinculá uno} a {nombre}{fin}')::text],
    ['el texto la deja tal cual', 'Llamá y {@accion|vinculá al arquitecto}',
     public.tareas_plantilla_texto('Llamá y {@accion|vinculá al arquitecto}', 'obra', v_obra, v_usuario)]
  ];
  v_fallan text := '';
  v_ok int := 0;
  i int;
BEGIN
  FOR i IN 1 .. array_length(v_casos, 1) LOOP
    IF v_casos[i][2] IS NOT DISTINCT FROM v_casos[i][3] THEN
      v_ok := v_ok + 1;
    ELSE
      v_fallan := v_fallan || format(E'\n  %s: esperado %s, obtenido %s', v_casos[i][1], v_casos[i][2], v_casos[i][3]);
    END IF;
  END LOOP;
  RAISE EXCEPTION '% / % ok%', v_ok, array_length(v_casos, 1), v_fallan;
END;
$$;
