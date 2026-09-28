-- sql/145 — contactos, tramo 4: el tipo de aviso de fusionar. En su propia
-- transacción: `sql/146` lo usa en `notificaciones_listar`, que se valida al
-- crearse.
--   persona_fusionada → el dueño de la que se va ("Marta Gómez se fusionó
--                       con la de Juan")
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'persona_fusionada';
