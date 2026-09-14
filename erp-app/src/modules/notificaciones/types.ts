import { z } from "zod";
import type { Database } from "@/lib/supabase/database.types";

export type TipoNotificacion = Database["public"]["Enums"]["tipo_notificacion"];

// El generador de tipos declara no-nulas las columnas de un `RETURNS TABLE`
// (mismo defecto que corrige `argsRpc` del lado de los argumentos). Tres de
// estas sí llegan en null: un alta aprobada no tiene `motivo`, un evento de
// sistema no tiene `actor`, y `etiqueta` queda vacía si la fila apuntada perdió
// su nombre. `destino` también: el aviso de una plantilla archivada no tiene
// adónde llevar (sql/055). Declararlas acá obliga a contemplarlo en la UI.
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

export type Avisos = { vencidas: number; vencen_hoy: number };

export const uuidSchema = z.string().uuid();
