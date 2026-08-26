-- Verificación de sql/020: un usuario desactivado pierde los permisos.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK. Correr después de aplicar sql/020.
--
-- Mismo mecanismo que rls_visibilidad_tareas.sql: se cambia a rol
-- `authenticated` y se setea request.jwt.claims para mover auth.uid().
--
-- Los ids no van hardcodeados: el test toma el primer usuario activo con algún
-- submódulo activo, así no queda atado a una base concreta.

BEGIN;

CREATE TEMP TABLE r (
  caso text,
  esperado text,
  obtenido text,
  ok boolean
) ON COMMIT DROP;
GRANT ALL ON r TO authenticated;

CREATE TEMP TABLE sujeto (usuario_id uuid, codigo text) ON COMMIT DROP;
GRANT ALL ON sujeto TO authenticated;

INSERT INTO sujeto (usuario_id, codigo)
SELECT us.usuario_id, s.codigo
FROM usuario_submodulos us
JOIN submodulos s ON s.id = us.submodulo_id
JOIN usuarios u ON u.id = us.usuario_id
WHERE us.activo AND s.activo AND u.activo
LIMIT 1;

-- 1. Con el usuario activo, el permiso existe.
DO $$
DECLARE
  v_usuario uuid;
  v_codigo text;
  v_tiene boolean;
BEGIN
  SELECT usuario_id, codigo INTO v_usuario, v_codigo FROM sujeto;

  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', v_usuario), true);
  PERFORM set_config('role', 'authenticated', true);

  v_tiene := tiene_permiso(v_codigo);
  INSERT INTO r VALUES ('1 activo: tiene su permiso', 'true', v_tiene::text, v_tiene);
END $$;

RESET ROLE;

UPDATE usuarios SET activo = false WHERE id = (SELECT usuario_id FROM sujeto);

-- 2. Desactivado: el mismo permiso, con las mismas filas en
--    usuario_submodulos, ya no vale.
-- 3. Sigue viendo su propia fila en `usuarios` — es lo que el proxy consulta
--    para echarlo; si RLS se la negara, `perfil` sería null y el corte
--    dependería de un dato ausente en vez del dato real.
DO $$
DECLARE
  v_usuario uuid;
  v_codigo text;
  v_tiene boolean;
  v_propias int;
BEGIN
  SELECT usuario_id, codigo INTO v_usuario, v_codigo FROM sujeto;

  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', v_usuario), true);
  PERFORM set_config('role', 'authenticated', true);

  v_tiene := tiene_permiso(v_codigo);
  INSERT INTO r VALUES ('2 desactivado: pierde el permiso', 'false', v_tiene::text, NOT v_tiene);

  SELECT count(*) INTO v_propias FROM usuarios WHERE id = v_usuario;
  INSERT INTO r VALUES ('3 desactivado: ve su propia fila', '1', v_propias::text, v_propias = 1);
END $$;

RESET ROLE;

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
