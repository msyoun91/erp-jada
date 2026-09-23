import { z } from "zod";

// El enum `tipo_notificacion` no tiene valores todavía (sql/107) y el generador
// lo tipa `unknown`. El primer evento lo pasa a
// `Database["public"]["Enums"]["tipo_notificacion"]`.
export type TipoNotificacion = never;

// El generador de tipos declara no-nulas las columnas de un `RETURNS TABLE`
// (mismo defecto que corrige `argsRpc` del lado de los argumentos). Varias
// llegan en null: un evento sin `motivo`, uno de sistema sin `actor`, una fila
// apuntada sin nombre, un aviso sin adónde llevar. Declararlas acá obliga a
// contemplarlo en la UI.
export type Notificacion = {
  id: string;
  tipo: TipoNotificacion;
  etiqueta: string | null;
  motivo: string | null;
  actor: string | null;
  destino: string | null;
  destino_id: string;
  leida: boolean;
  created_at: string;
};

export const uuidSchema = z.string().uuid();
