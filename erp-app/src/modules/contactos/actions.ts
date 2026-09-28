"use server";

import { revalidatePath } from "next/cache";
import { argsRpc } from "@/lib/supabase/rpc";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { idSchema } from "@/lib/validacion";
import {
  buscarSchema,
  cerrarSchema,
  compartirEmpresaSchema,
  crearYVincularSchema,
  editarPersonaSchema,
  empresaSchema,
  equipoEmpresaSchema,
  parecidasSchema,
  personaEmpresaSchema,
  personaSchema,
  resolverSchema,
  rolesSchema,
  transferirPersonaSchema,
  vincularSchema,
  type CerrarForm,
  type CompartirEmpresaForm,
  type CrearYVincularForm,
  type EditarPersonaForm,
  type EmpresaForm,
  type EquipoEmpresaForm,
  type ParecidaAviso,
  type ParecidasForm,
  type PersonaEmpresaForm,
  type PersonaForm,
  type ResolverForm,
  type RolesForm,
  type TransferirPersonaForm,
  type VincularForm,
} from "./types";

// Quién puede qué lo deciden las policies y los triggers de `sql/127`: acá
// solo se valida la forma, se escribe y se traduce el error. Un vínculo se
// muestra en la ficha del registro, así que se revalida todo el árbol.

function fallo(error: unknown) {
  return { success: false as const, error: mensajeError(error) };
}

function invalido(issues: { message: string }[]) {
  return { success: false as const, error: issues[0].message };
}

function listo() {
  revalidatePath("/", "layout");
  return { success: true as const };
}

function validarId(id: unknown) {
  const parsed = idSchema.safeParse(id);
  return parsed.success ? { id: parsed.data } : { error: invalido(parsed.error.issues) };
}

// ---------- Persona ----------

// El id se genera acá: sin RETURNING, la RLS de SELECT no se interpone.
export async function crearPersona(input: PersonaForm) {
  const parsed = personaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const id = crypto.randomUUID();
  const supabase = await createClient();
  const { error } = await supabase.from("contactos_personas").insert({ id, ...parsed.data });
  if (error) return fallo(error);
  revalidatePath("/contactos", "layout");
  return { success: true as const, id };
}

export async function editarPersona(input: EditarPersonaForm) {
  const parsed = editarPersonaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, contacto, ...cambios } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase
    .from("contactos_personas")
    .update({ ...cambios, ...contacto })
    .eq("id", id);
  return error ? fallo(error) : listo();
}

export async function transferirPersona(input: TransferirPersonaForm) {
  const parsed = transferirPersonaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("contactos_transferir_persona", {
    p_persona: parsed.data.id,
    p_responsable: parsed.data.responsable_id,
  });
  return error ? fallo(error) : listo();
}

export async function desactivarPersona(id: string) {
  const v = validarId(id);
  if (v.error) return v.error;
  const supabase = await createClient();
  const { error } = await supabase.rpc("contactos_desactivar_persona", { p_persona: v.id });
  return error ? fallo(error) : listo();
}

export async function reactivarPersona(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("contactos_personas").update({ activo: true }).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

// "Ver contacto" deja registro en `contactos_accesos`: se llama al tocar el
// botón, nunca al cargar la ficha.
export async function verContacto(persona: string) {
  const parsed = idSchema.safeParse(persona);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_ver_contacto", { p_persona: parsed.data });
  if (error) return fallo(error);
  return { success: true as const, contacto: data[0] ?? { telefono: null, email: null } };
}

export async function historialContacto(persona: string) {
  const parsed = idSchema.safeParse(persona);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_historial_contacto", { p_persona: parsed.data });
  if (error) return fallo(error);
  return { success: true as const, historial: data };
}

// ---------- Empresa ----------

export async function guardarEmpresa(input: EmpresaForm) {
  const parsed = empresaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...datos } = parsed.data;
  const supabase = await createClient();
  if (id) {
    const { error } = await supabase.from("contactos_empresas").update(datos).eq("id", id);
    return error ? fallo(error) : listo();
  }
  const nueva = crypto.randomUUID();
  const { error } = await supabase.from("contactos_empresas").insert({ id: nueva, ...datos });
  if (error) return fallo(error);
  revalidatePath("/contactos", "layout");
  return { success: true as const, id: nueva };
}

export async function asignarEquipoEmpresa(input: EquipoEmpresaForm) {
  const parsed = equipoEmpresaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("contactos_empresas")
    .update({ equipo_id: parsed.data.equipo_id })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function compartirEmpresa(input: CompartirEmpresaForm) {
  const parsed = compartirEmpresaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("contactos_compartir_empresa", {
    p_empresa: parsed.data.id,
    p_equipo: parsed.data.equipo_id,
    p_compartir: parsed.data.compartir,
  });
  return error ? fallo(error) : listo();
}

export async function desactivarEmpresa(id: string) {
  const v = validarId(id);
  if (v.error) return v.error;
  const supabase = await createClient();
  const { error } = await supabase.rpc("contactos_desactivar_empresa", { p_empresa: v.id });
  return error ? fallo(error) : listo();
}

export async function reactivarEmpresa(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("contactos_empresas").update({ activo: true }).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

// ---------- Persona ↔ empresa ----------

export async function sumarEmpresa(input: PersonaEmpresaForm) {
  const parsed = personaEmpresaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { desde, ...fila } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase
    .from("contactos_persona_empresa")
    .insert({ ...fila, ...(desde ? { desde } : {}) });
  return error ? fallo(error) : listo();
}

export async function cerrarPersonaEmpresa(input: CerrarForm) {
  const parsed = cerrarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("contactos_persona_empresa")
    .update({ hasta: parsed.data.hasta })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function desactivarPersonaEmpresa(id: string) {
  const v = validarId(id);
  if (v.error) return v.error;
  const supabase = await createClient();
  const { error } = await supabase.rpc("contactos_desactivar_persona_empresa", { p_relacion: v.id });
  return error ? fallo(error) : listo();
}

// ---------- Vínculos ----------

export async function buscarVinculables(texto: string) {
  const parsed = buscarSchema.safeParse(texto);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_vinculables", { p_texto: parsed.data });
  if (error) return fallo(error);
  return { success: true as const, resultados: data };
}

// La empresa de una persona: las que ve quien escribe (CO013), no solo las de
// su equipo. La RLS decide cuáles.
export async function buscarEmpresas(texto: string) {
  const parsed = buscarSchema.safeParse(texto);
  if (!parsed.success) return invalido(parsed.error.issues);
  const patron = `%${parsed.data.replace(/[\\%_]/g, "\\$&")}%`;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("contactos_empresas")
    .select("id, nombre")
    .eq("activo", true)
    .ilike("nombre", patron)
    .order("nombre")
    .limit(8);
  if (error) return fallo(error);
  return { success: true as const, resultados: data };
}

// El filtro de Auditoría: solo nombres de personas con algún acceso, sin abrir
// la agenda (`contactos_auditoria_personas`).
export async function buscarAuditadas(texto: string) {
  const parsed = buscarSchema.safeParse(texto);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_auditoria_personas", { p_texto: parsed.data });
  if (error) return fallo(error);
  return { success: true as const, resultados: data };
}

export async function vincular(input: VincularForm) {
  const parsed = vincularSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("contactos_vinculos").insert(parsed.data);
  return error ? fallo(error) : listo();
}

export async function crearYVincular(input: CrearYVincularForm) {
  const parsed = crearYVincularSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc(
    "contactos_crear_y_vincular",
    argsRpc<"contactos_crear_y_vincular">({
      p_ente: d.ente,
      p_registro: d.registro_id,
      p_roles: d.roles,
      p_tipo: d.tipo,
      p_nombre: d.nombre,
      p_telefono: d.telefono,
      p_email: d.email,
      p_empresa_id: d.empresa_id,
      p_empresa_nombre: d.empresa_nombre,
      p_cargo: d.cargo,
    })
  );
  return error ? fallo(error) : listo();
}

export async function cambiarRoles(input: RolesForm) {
  const parsed = rolesSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("contactos_vinculos")
    .update({ roles: parsed.data.roles })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function cerrarVinculo(input: CerrarForm) {
  const parsed = cerrarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("contactos_vinculos")
    .update({ hasta: parsed.data.hasta })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function desactivarVinculo(id: string) {
  const v = validarId(id);
  if (v.error) return v.error;
  const supabase = await createClient();
  const { error } = await supabase.rpc("contactos_desactivar_vinculo", { p_vinculo: v.id });
  return error ? fallo(error) : listo();
}

// ---------- Altas parecidas ----------

// De lo que no es tuyo, nombre, dueño y equipo: lo recorta la función.
export async function buscarParecidas(input: ParecidasForm) {
  const parsed = parecidasSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "contactos_parecidas",
    argsRpc<"contactos_parecidas">({ p_tipo: d.tipo, p_nombre: d.nombre, p_telefono: d.telefono, p_email: d.email, p_id: d.id })
  );
  return error ? fallo(error) : { success: true as const, resultados: data as ParecidaAviso[] };
}

export async function resolverContacto(input: ResolverForm) {
  const parsed = resolverSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc(
    "contactos_resolver",
    argsRpc<"contactos_resolver">({
      p_tipo: d.tipo,
      p_id: d.id,
      p_decision: d.decision,
      p_motivo: d.motivo,
      p_existente: d.existente,
      p_vincular: d.vincular,
    })
  );
  return error ? fallo(error) : listo();
}
