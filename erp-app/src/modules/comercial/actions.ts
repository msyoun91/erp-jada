"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import {
  editarEmpresaSchema,
  editarObraSchema,
  editarPersonaSchema,
  editarProspectoSchema,
  editarRelacionEmpresaSchema,
  editarRelacionPersonaSchema,
  empresaSchema,
  obraSchema,
  personaSchema,
  prospectoSchema,
  relacionEmpresaSchema,
  relacionPersonaSchema,
  type EditarEmpresaForm,
  type EditarObraForm,
  type EditarPersonaForm,
  type EditarProspectoForm,
  type EditarRelacionEmpresaForm,
  type EditarRelacionPersonaForm,
  type EmpresaForm,
  type ObraForm,
  type PersonaForm,
  type ProspectoForm,
  type RelacionEmpresaForm,
  type RelacionPersonaForm,
} from "./types";

// Sin chequeo de permisos acá: todas estas actions usan el cliente normal (no
// service_role), así que la RLS ya autoriza cada operación a nivel fila —
// duplicar el chequeo en la action no agrega barrera, solo un segundo lugar
// donde desincronizarse. Mismo criterio que modules/tareas/actions.ts.
async function usuarioActualId() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");
  return user.id;
}

// Las cuatro vistas del módulo leen del mismo grafo (una empresa nueva aparece
// en el selector de la ficha de obra), así que se revalida el layout entero.
function revalidar() {
  revalidatePath("/comercial", "layout");
}

type Resultado = { success: true } | { success: false; error: string };

export async function crearEmpresa(input: EmpresaForm): Promise<Resultado> {
  const parsed = empresaSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("empresas")
    .insert({ ...parsed.data, creado_por: await usuarioActualId() });

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function editarEmpresa(input: EditarEmpresaForm): Promise<Resultado> {
  const parsed = editarEmpresaSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const { id, ...datos } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.from("empresas").update(datos).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function desactivarEmpresa(id: string): Promise<Resultado> {
  const supabase = await createClient();
  const { error } = await supabase.from("empresas").update({ activo: false }).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function crearPersona(input: PersonaForm): Promise<Resultado> {
  const parsed = personaSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("personas")
    .insert({ ...parsed.data, creado_por: await usuarioActualId() });

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function editarPersona(input: EditarPersonaForm): Promise<Resultado> {
  const parsed = editarPersonaSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const { id, ...datos } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.from("personas").update(datos).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function desactivarPersona(id: string): Promise<Resultado> {
  const supabase = await createClient();
  const { error } = await supabase.from("personas").update({ activo: false }).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function crearObra(input: ObraForm): Promise<Resultado> {
  const parsed = obraSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("obras")
    .insert({ ...parsed.data, creado_por: await usuarioActualId() });

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function editarObra(input: EditarObraForm): Promise<Resultado> {
  const parsed = editarObraSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const { id, ...datos } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.from("obras").update(datos).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

// El prospecto y las relaciones caen con la obra por trigger (cascada en
// Postgres, no acá).
export async function desactivarObra(id: string): Promise<Resultado> {
  const supabase = await createClient();
  const { error } = await supabase.from("obras").update({ activo: false }).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function crearProspecto(input: ProspectoForm): Promise<Resultado> {
  const parsed = prospectoSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("comercial_prospectos")
    .insert({ ...parsed.data, creado_por: await usuarioActualId() });

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function editarProspecto(input: EditarProspectoForm): Promise<Resultado> {
  const parsed = editarProspectoSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const { id, ...datos } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.from("comercial_prospectos").update(datos).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function desactivarProspecto(id: string): Promise<Resultado> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("comercial_prospectos")
    .update({ activo: false })
    .eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function guardarRelacionEmpresa(
  input: RelacionEmpresaForm | EditarRelacionEmpresaForm
): Promise<Resultado> {
  const supabase = await createClient();

  if ("id" in input && input.id) {
    const parsed = editarRelacionEmpresaSchema.safeParse(input);
    if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

    const { error } = await supabase
      .from("obra_empresa")
      .update({
        empresa_id: parsed.data.empresa_id,
        roles: parsed.data.roles,
        observaciones: parsed.data.observaciones,
      })
      .eq("id", parsed.data.id);

    if (error) return { success: false, error: mensajeError(error) };
    revalidar();
    return { success: true };
  }

  const parsed = relacionEmpresaSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const { error } = await supabase.from("obra_empresa").insert(parsed.data);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function quitarRelacionEmpresa(id: string): Promise<Resultado> {
  const supabase = await createClient();
  const { error } = await supabase.from("obra_empresa").update({ activo: false }).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

// La relación y su comisión se guardan en una sola llamada: la función SQL las
// mantiene consistentes y, al ser SECURITY INVOKER, quien no tiene
// `comercial_comision` no puede tocar ni borrar el porcentaje que ya existía.
export async function guardarRelacionPersona(
  input: RelacionPersonaForm | EditarRelacionPersonaForm
): Promise<Resultado> {
  const editando = "id" in input && Boolean(input.id);
  const parsed = editando
    ? editarRelacionPersonaSchema.safeParse(input)
    : relacionPersonaSchema.safeParse({ ...input, id: undefined });
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.rpc("guardar_obra_persona", {
    p_id: editando ? (input as EditarRelacionPersonaForm).id : null,
    p_obra_id: parsed.data.obra_id,
    p_persona_id: parsed.data.persona_id,
    p_empresa_id: parsed.data.empresa_id,
    p_roles: parsed.data.roles,
    p_es_referente: parsed.data.es_referente,
    p_porcentaje_comision: parsed.data.porcentaje_comision,
    p_observaciones: parsed.data.observaciones,
  });

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}

export async function quitarRelacionPersona(id: string): Promise<Resultado> {
  const supabase = await createClient();
  const { error } = await supabase.from("obra_persona").update({ activo: false }).eq("id", id);

  if (error) return { success: false, error: mensajeError(error) };
  revalidar();
  return { success: true };
}
