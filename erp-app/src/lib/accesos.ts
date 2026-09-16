"use server";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { argsRpc } from "@/lib/supabase/rpc";
import { mensajeError } from "@/lib/utils";

// Quién puede abrir un registro, preguntado por usuario (sql/062) y aplicado
// al asignar/relacionar/disparar (sql/063). Vive en lib/ porque lo usan dos
// módulos: Tareas (asignar, relacionar) y Obras (ensayar un cambio de estado).
export type FilaSinAcceso = {
  usuario_id: string;
  usuario: string;
  ente: string;
  registro_id: string;
  etiqueta: string | null;
  compartible: boolean;
};

const parSchema = z.object({
  usuario_id: z.string().uuid(),
  ente: z.string().min(1).max(50),
  registro_id: z.string().uuid(),
});

export async function sinAcceso(
  pares: { usuario_id: string; ente: string; registro_id: string }[],
): Promise<{ success: true; filas: FilaSinAcceso[] } | { success: false; error: string }> {
  const parsed = z.array(parSchema).max(200).safeParse(pares);
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "sin_acceso",
    argsRpc<"sin_acceso">({ p_pares: parsed.data }),
  );
  if (error) return { success: false, error: mensajeError(error) };
  return { success: true, filas: data as FilaSinAcceso[] };
}

export async function compartirRegistros(
  selecciones: { usuario_id: string; ente: string; registro_id: string }[],
): Promise<{ success: true } | { success: false; error: string }> {
  const parsed = z.array(parSchema).max(200).safeParse(selecciones);
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc(
    "compartir_registros",
    argsRpc<"compartir_registros">({ p_selecciones: parsed.data }),
  );
  if (error) return { success: false, error: mensajeError(error) };
  return { success: true };
}
