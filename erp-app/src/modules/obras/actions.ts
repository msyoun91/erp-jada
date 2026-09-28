"use server";

import { revalidatePath } from "next/cache";
import type { Database } from "@/lib/supabase/database.types";
import { argsRpc } from "@/lib/supabase/rpc";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { idSchema } from "@/lib/validacion";
import {
  altaSchema,
  estadoSchema,
  obraSchema,
  participanteSchema,
  transferirSchema,
  type AltaForm,
  type EstadoForm,
  type ObraForm,
  type ParticipanteForm,
  type TransferirForm,
} from "./types";

// Quién puede qué lo deciden las policies y los triggers de `sql/126`: acá
// solo se valida la forma, se escribe y se traduce el error.

function fallo(error: unknown) {
  return { success: false as const, error: mensajeError(error) };
}

function invalido(issues: { message: string }[]) {
  return { success: false as const, error: issues[0].message };
}

function listo() {
  revalidatePath("/obras", "layout");
  return { success: true as const };
}

async function editarFila(id: unknown, cambios: Database["public"]["Tables"]["obras"]["Update"]) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("obras").update(cambios).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

export async function crearObra(input: AltaForm) {
  const parsed = altaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { data: id, error } = await supabase.rpc(
    "obras_alta",
    argsRpc<"obras_alta">({
      p_nombre: d.nombre,
      p_direccion: d.direccion,
      p_origen: d.origen,
      p_tipo: d.tipo,
      p_localidad: d.localidad,
      p_notas: d.notas,
      p_compra_estimada: d.compra_estimada,
      p_estado: d.estado,
      p_quien_persona: d.quien_persona,
      p_quien_empresa: d.quien_empresa,
      p_quien_nuevo_tipo: d.quien_nuevo_tipo,
      p_quien_nuevo_nombre: d.quien_nuevo_nombre,
      p_quien_nuevo_telefono: d.quien_nuevo_telefono,
      p_quien_nuevo_email: d.quien_nuevo_email,
    })
  );
  if (error) return fallo(error);
  revalidatePath("/obras", "layout");
  return { success: true as const, id };
}

export async function editarObra(input: ObraForm) {
  const parsed = obraSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...cambios } = parsed.data;
  return editarFila(id, cambios);
}

export async function cambiarEstado(input: EstadoForm) {
  const parsed = estadoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, estado, motivo_perdida, estado_nota } = parsed.data;
  return editarFila(id, { estado, motivo_perdida, estado_nota });
}

export async function transferirObra(input: TransferirForm) {
  const parsed = transferirSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("obras_transferir", {
    p_obra: parsed.data.id,
    p_responsable: parsed.data.responsable_id,
    p_quedarme: parsed.data.quedarme,
  });
  return error ? fallo(error) : listo();
}

export async function desactivarObra(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("obras_desactivar", { p_obra: parsed.data });
  return error ? fallo(error) : listo();
}

export async function reactivarObra(id: string) {
  return editarFila(id, { activo: true });
}

export async function sumarParticipante(input: ParticipanteForm) {
  const parsed = participanteSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("obras_participantes").insert(parsed.data);
  return error ? fallo(error) : listo();
}

export async function quitarParticipante(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("obras_participantes").update({ activo: false }).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}
