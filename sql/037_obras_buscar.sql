-- ============================================================
-- 037 — Un buscador para las tres entidades
--
-- Con las obras privadas por responsable y la agenda creciendo, encontrar algo
-- cargado hace seis meses obligaba a adivinar en qué tab estaba y buscar tres
-- veces. Una sola barra arriba del módulo busca obra, empresa y persona y
-- lleva a la ficha.
--
-- **No inventa visibilidad.** Cada entidad se busca con el alcance que ya
-- tiene: la obra es de su responsable, la empresa es compartida, la persona
-- tiene alcance por fila. Por eso `obras_buscar` es SECURITY INVOKER y las
-- ramas de obras y empresas son `SELECT` directos — las policies deciden, y no
-- hay una segunda copia de la regla que se pueda desincronizar.
--
-- La rama de personas es la única que necesita ver más que quien pregunta, y
-- va aparte por eso mismo: `obras_buscar_personas` es DEFINER y devuelve
-- identidad mínima —nombre, apellido y empresa principal, nunca contacto— de
-- las que están fuera de alcance, con `visible = false`. Es la misma capa que
-- `obras_buscar_duplicados_persona`: encontrar a alguien no es abrirle la
-- ficha, y el contacto sigue saliendo solo por `obras_ficha_persona()`, que
-- deja registro.
--
-- Es el mismo corte que la 033 le hizo a la detección de duplicados —el match
-- crudo por un lado, el enmascarado por otro—, con los roles invertidos: acá
-- lo enmascarado es lo interno y lo que se llama desde la app es el envoltorio
-- INVOKER.
--
-- **La obra ajena no aparece.** `obras_buscar_duplicados_obra` la devuelve con
-- `nombre`, `direccion` y `localidad` en NULL, así que en una lista de
-- resultados sería una fila sin nada que mostrar. El aviso ciego ya cubre el
-- caso que importa —no cargar dos veces el mismo edificio— y salta al crear,
-- que es cuando sirve.
--
-- El match es substring sobre las columnas `_norm`: sin acentos, sin
-- mayúsculas y con la puntuación comida, así que "peña" encuentra "Peña" y un
-- `%` tipeado en la barra no es un comodín, es un espacio. No es difuso a
-- propósito: el parecido de `pg_trgm` sirve para "esto ya está cargado", no
-- para "empecé a escribir el nombre" —similarity('gonz', 'juan gonzalez') no
-- llega ni cerca del umbral—.
--
-- Piso de 2 caracteres y tope de 5 por tipo. El piso vive en `patron`, que con
-- menos de 2 no devuelve fila y deja las tres ramas sin nada contra qué
-- joinear: escrito una vez, no tres.
--
-- Verificación: `sql/tests/obras_037.sql`.
-- ============================================================

-- ============================================================
-- 1. Personas — identidad mínima de las que no se ven
--
-- El guard y la cláusula de congeladas son los de
-- `obras_buscar_duplicados_persona`: quien no tiene acceso al módulo no busca
-- nada, y la fila que espera autorización la ve solo quien la cargó.
--
-- `cargada_por` es el nombre del usuario que la cargó, no de la persona: sin
-- él, la fila fuera de alcance dice "existe" y nada más. Mismo criterio que el
-- aviso ciego de obras, que devuelve el nombre del responsable — alcanza para
-- ir a preguntar, no para leer la agenda del otro.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar_personas(p_texto text)
RETURNS TABLE (
  persona_id  uuid,
  nombre      text,
  apellido    text,
  empresa     text,
  visible     boolean,
  cargada_por text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  WITH patron AS (
    SELECT obras_normalizar(p_texto) || '%'        AS empieza,
           '%' || obras_normalizar(p_texto) || '%' AS contiene
    WHERE length(obras_normalizar(p_texto)) >= 2
  )
  SELECT p.id, p.nombre, p.apellido,
         (
           SELECT e.razon_social
           FROM obras_persona_empresa pe
           JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo
           WHERE pe.persona_id = p.id AND pe.activo
           ORDER BY pe.es_principal DESC
           LIMIT 1
         ),
         obras_puede_ver_persona(p.id),
         u.nombre
  FROM patron x
  JOIN obras_personas p ON p.activo AND p.nombre_norm LIKE x.contiene
  LEFT JOIN usuarios u ON u.id = p.creado_por
  WHERE (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (NOT p.pendiente OR p.creado_por = (SELECT auth.uid()))
  ORDER BY obras_puede_ver_persona(p.id) DESC,
           (p.nombre_norm LIKE x.empieza) DESC,
           p.nombre_norm
  LIMIT 5;
$$;

-- ============================================================
-- 2. La barra — una llamada, tres tipos
--
-- INVOKER: las ramas de obras y empresas pasan por RLS, que es donde vive la
-- visibilidad de las dos. Por eso `obras_buscar_personas` necesita EXECUTE
-- para `authenticated` aunque solo la llame esta función: corre como quien
-- pregunta, no como el dueño.
--
-- `orden` y `rango` no salen: ordenan y se quedan adentro. `rango` es "no
-- empieza con lo que escribiste", que pesa antes que el nombre para que
-- buscar "cabildo" no deje "Cabildo 2340" afuera del tope por cinco obras que
-- lo mencionan a mitad de frase. En personas `rango` es "no la podés ver": lo
-- que está a tu alcance va primero.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar(p_texto text)
RETURNS TABLE (
  tipo        text,
  id          uuid,
  titulo      text,
  subtitulo   text,
  visible     boolean,
  cargada_por text
)
LANGUAGE sql STABLE SET search_path = public
AS $$
  WITH patron AS (
    SELECT obras_normalizar(p_texto) || '%'        AS empieza,
           '%' || obras_normalizar(p_texto) || '%' AS contiene
    WHERE length(obras_normalizar(p_texto)) >= 2
  ),
  encontrado AS (
    (
      SELECT 1                                                      AS orden,
             (o.nombre_norm NOT LIKE x.empieza)                     AS rango,
             'obra'::text                                           AS tipo,
             o.id                                                   AS id,
             o.nombre                                               AS titulo,
             nullif(concat_ws(' · ', o.direccion, o.localidad), '')  AS subtitulo,
             true                                                   AS visible,
             NULL::text                                             AS cargada_por
      FROM patron x
      JOIN obras o ON o.activo
        AND (o.nombre_norm LIKE x.contiene
          OR o.direccion_norm LIKE x.contiene
          OR o.localidad_norm LIKE x.contiene)
      ORDER BY rango, o.nombre
      LIMIT 5
    )
    UNION ALL
    (
      SELECT 2,
             (e.razon_social_norm NOT LIKE x.empieza),
             'empresa',
             e.id,
             e.razon_social,
             nullif(concat_ws(' · ', e.nombre_comercial, e.localidad), ''),
             true,
             NULL
      FROM patron x
      JOIN obras_empresas e ON e.activo
        AND (e.razon_social_norm LIKE x.contiene
          OR e.nombre_comercial_norm LIKE x.contiene)
      ORDER BY 2, e.razon_social
      LIMIT 5
    )
    UNION ALL
    (
      SELECT 3,
             NOT p.visible,
             'persona',
             p.persona_id,
             btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
             p.empresa,
             p.visible,
             p.cargada_por
      FROM obras_buscar_personas(p_texto) p
    )
  )
  SELECT r.tipo, r.id, r.titulo, r.subtitulo, r.visible, r.cargada_por
  FROM encontrado r
  ORDER BY r.orden, r.rango, r.titulo;
$$;

-- ============================================================
-- 3. Superficie RPC
--
-- Las dos se llaman desde la app: `obras_buscar` desde la barra y
-- `obras_buscar_personas` desde `obras_buscar`, que al ser INVOKER la ejecuta
-- con el rol de quien pregunta. Exponerla no agrega nada que no dé ya
-- `obras_buscar_duplicados_persona`: identidad mínima, con el mismo guard.
-- ============================================================
REVOKE EXECUTE ON FUNCTION obras_buscar(text)          FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_buscar_personas(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION obras_buscar(text)          TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_personas(text) TO authenticated;
