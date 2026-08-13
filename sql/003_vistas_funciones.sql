-- Estructura de permisos: módulo → 1+ vistas → cada vista 0+ funciones.
-- Antes: tipo 'seccion'/'funcion' sin relación explícita (función solo ligada
-- a modulo, no a una vista puntual — no soportaba módulos con 2+ vistas).
-- Correr en Supabase SQL Editor.

-- ============================================================
-- Renombrar 'seccion' -> 'vista' (mismo concepto, nombre correcto)
-- ============================================================
ALTER TYPE tipo_submodulo RENAME VALUE 'seccion' TO 'vista';

-- ============================================================
-- submodulos.vista_id — funcion apunta a su vista dueña
-- ============================================================
ALTER TABLE submodulos ADD COLUMN IF NOT EXISTS vista_id uuid REFERENCES submodulos(id);

-- vista_id debe apuntar a una fila tipo='vista' del mismo modulo
-- (no expresable como CHECK simple — requiere trigger).
CREATE OR REPLACE FUNCTION validar_vista_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.vista_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM submodulos
      WHERE id = NEW.vista_id AND tipo = 'vista' AND modulo = NEW.modulo
    ) THEN
      RAISE EXCEPTION 'vista_id debe referenciar una vista del mismo modulo';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS check_vista_id ON submodulos;
CREATE TRIGGER check_vista_id
  BEFORE INSERT OR UPDATE ON submodulos
  FOR EACH ROW EXECUTE FUNCTION validar_vista_id();

-- ============================================================
-- Backfill: usuarios_gestionar (funcion) -> vista_id = usuarios_ver
-- (antes del CHECK: filas existentes de tipo funcion no tienen vista_id todavía)
-- ============================================================
UPDATE submodulos
SET vista_id = (SELECT id FROM submodulos WHERE codigo = 'usuarios_ver')
WHERE codigo = 'usuarios_gestionar';

-- vista: sin vista_id. funcion: vista_id obligatorio.
DO $$
BEGIN
  ALTER TABLE submodulos
    ADD CONSTRAINT submodulos_vista_id_check
    CHECK (
      (tipo = 'vista' AND vista_id IS NULL) OR
      (tipo = 'funcion' AND vista_id IS NOT NULL)
    );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
