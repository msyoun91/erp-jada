-- 046_obras_estados_comerciales
-- estado_obra: sale 'en_construccion', entran 'en_cotizacion' / 'en_ejecucion' / 'en_postventa'.
-- Las obras en 'en_construccion' (4 al aplicar, todas seed dummy) pasan a 'en_ejecucion'.
-- Postgres no permite quitar un valor de un enum: se reconstruye el tipo.

ALTER TYPE estado_obra RENAME TO estado_obra_old;

CREATE TYPE estado_obra AS ENUM (
  'idea', 'en_cotizacion', 'en_ejecucion', 'en_postventa', 'perdida', 'terminada'
);

ALTER TABLE obras ALTER COLUMN estado DROP DEFAULT;
ALTER TABLE obras DROP CONSTRAINT obras_perdida_con_motivo;

ALTER TABLE obras
  ALTER COLUMN estado TYPE estado_obra
  USING (CASE estado::text
    WHEN 'en_construccion' THEN 'en_ejecucion'
    ELSE estado::text
  END::estado_obra);

ALTER TABLE obras ALTER COLUMN estado SET DEFAULT 'idea';
ALTER TABLE obras ADD CONSTRAINT obras_perdida_con_motivo
  CHECK (estado <> 'perdida'::estado_obra OR motivo_perdida IS NOT NULL);

DROP TYPE estado_obra_old;
