"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { argsRpc } from "@/lib/supabase/rpc";
import { mensajeError } from "@/lib/utils";
import {
  getEmpresas,
  getContactosExclusivosObra,
  getContactosExclusivosEmpresa,
} from "./queries";
import {
  crearObraSchema,
  editarObraSchema,
  crearEmpresaSchema,
  editarEmpresaSchema,
  crearPersonaSchema,
  editarPersonaSchema,
  vincularEmpresaSchema,
  vincularPersonaSchema,
  vincularPersonaEmpresaSchema,
  referenteSchema,
  transferirObraSchema,
  transferirPersonaSchema,
  transferirEmpresaSchema,
  compartirSchema,
  resolverPendienteSchema,
  type CrearObraForm,
  type EditarObraForm,
  type CrearEmpresaForm,
  type EditarEmpresaForm,
  type CrearPersonaForm,
  type EditarPersonaForm,
  type VincularEmpresaForm,
  type VincularPersonaForm,
  type VincularPersonaEmpresaForm,
  type ReferenteForm,
  type TransferirObraForm,
  type TransferirPersonaForm,
  type TransferirEmpresaForm,
  type CompartirForm,
  type ResolverPendienteForm,
  type PersonaDeEmpresa,
  type SimilarPendiente,
  type TipoPendiente,
  type DuplicadoEmpresa,
  type DuplicadoObra,
  type DuplicadoPersona,
  type ResultadoBusqueda,
} from "./types";

// Sin chequeo de permisos acá: estas actions usan el cliente normal, así que
// RLS ya autoriza cada operación a nivel fila. Mismo criterio que
// modules/tareas/actions.ts.
async function usuarioActualId() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");
  return user.id;
}

const SIN_FILAS =
  "No se pudo guardar: el registro ya no existe o no tenés permiso para modificarlo";

// Un UPDATE que RLS rechaza no falla: afecta 0 filas y vuelve sin error.
function errorDeUpdate({ error, count }: { error: unknown; count: number | null }) {
  if (error) return mensajeError(error);
  return count === 0 ? SIN_FILAS : null;
}

function revalidarObras(id?: string) {
  revalidatePath("/obras");
  if (id) revalidatePath(`/obras/${id}`);
}

export async function crearObra(input: CrearObraForm) {
  const parsed = crearObraSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  // `pendiente` lo decide el trigger de sql/033 con el mismo criterio de
  // parecido que muestra el aviso: si vuelve en true la obra existe pero está
  // congelada hasta que la autoricen, y la pantalla tiene que decirlo.
  const { data, error } = await supabase
    .from("obras")
    .insert({ ...parsed.data, responsable_id: await usuarioActualId() })
    .select("id, pendiente")
    .single();

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidarObras();
  revalidatePath("/obras/pendientes");
  return { success: true as const, id: data.id, pendiente: data.pendiente };
}

export async function editarObra(input: EditarObraForm) {
  const parsed = editarObraSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, ...campos } = parsed.data;

  const { error, count } = await supabase
    .from("obras")
    .update(campos, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidarObras(id);
  return { success: true as const };
}

// `activo` no tiene GRANT de UPDATE: desactivar es un permiso propio y pasa por
// función que lo verifica.
export async function setActivoObra(id: string, activo: boolean) {
  const supabase = await createClient();

  const { error } = await supabase.rpc("obras_set_activo", {
    p_obra_id: id,
    p_activo: activo,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidarObras(id);
  return { success: true as const };
}

// Igual que `activo`: `responsable_id` no tiene GRANT. Además la función valida
// que el destino tenga acceso al módulo — transferirle una obra a alguien que
// no puede abrirla la haría desaparecer para todos menos para quien transfiere.
export async function transferirObra(input: TransferirObraForm) {
  const parsed = transferirObraSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc("obras_transferir", {
    p_obra_id: parsed.data.obra_id,
    p_a_usuario_id: parsed.data.a_usuario_id,
    p_contactos_exclusivos: parsed.data.contactos_exclusivos,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidarObras(parsed.data.obra_id);
  revalidatePath("/obras/personas");
  revalidatePath("/obras/empresas");
  return { success: true as const };
}

export async function transferirPersona(input: TransferirPersonaForm) {
  const parsed = transferirPersonaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc("obras_transferir_persona", {
    p_persona_id: parsed.data.persona_id,
    p_a_usuario_id: parsed.data.a_usuario_id,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/obras/personas");
  revalidatePath(`/obras/personas/${parsed.data.persona_id}`);
  return { success: true as const };
}

export async function transferirEmpresa(input: TransferirEmpresaForm) {
  const parsed = transferirEmpresaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc("obras_transferir_empresa", {
    p_empresa_id: parsed.data.empresa_id,
    p_a_usuario_id: parsed.data.a_usuario_id,
    p_personas_exclusivas: parsed.data.personas_exclusivas,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/obras/empresas");
  revalidatePath(`/obras/empresas/${parsed.data.empresa_id}`);
  revalidatePath("/obras/personas");
  return { success: true as const };
}

// ── Compartir / revocar (dueño desde la ficha) ───────────────

export async function compartirPersona(input: CompartirForm) {
  const parsed = compartirSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("obras_compartir_persona", {
    p_persona_id: parsed.data.id,
    p_usuario_id: parsed.data.usuario_id,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath(`/obras/personas/${parsed.data.id}`);
  return { success: true as const };
}

export async function revocarPersona(personaId: string, usuarioId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("obras_revocar_persona", {
    p_persona_id: personaId,
    p_usuario_id: usuarioId,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath(`/obras/personas/${personaId}`);
  return { success: true as const };
}

export async function compartirEmpresa(input: CompartirForm) {
  const parsed = compartirSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("obras_compartir_empresa", {
    p_empresa_id: parsed.data.id,
    p_usuario_id: parsed.data.usuario_id,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath(`/obras/empresas/${parsed.data.id}`);
  return { success: true as const };
}

export async function revocarEmpresa(empresaId: string, usuarioId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("obras_revocar_empresa", {
    p_empresa_id: empresaId,
    p_usuario_id: usuarioId,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath(`/obras/empresas/${empresaId}`);
  return { success: true as const };
}

// Lecturas que un componente cliente necesita antes de transferir: el checklist
// de contactos exclusivos. Van como actions porque las llama el panel.
export async function contactosExclusivosObra(obraId: string) {
  return getContactosExclusivosObra(obraId);
}

export async function contactosExclusivosEmpresa(empresaId: string) {
  return getContactosExclusivosEmpresa(empresaId);
}

export async function crearEmpresa(input: CrearEmpresaForm) {
  const parsed = crearEmpresaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_empresas")
    .insert({ ...parsed.data, creado_por: await usuarioActualId() })
    .select("id, pendiente")
    .single();

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/obras/empresas");
  revalidatePath("/obras/pendientes");
  return { success: true as const, id: data.id, pendiente: data.pendiente };
}

export async function editarEmpresa(input: EditarEmpresaForm) {
  const parsed = editarEmpresaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, ...campos } = parsed.data;

  const { error, count } = await supabase
    .from("obras_empresas")
    .update(campos, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/obras/empresas");
  revalidatePath(`/obras/empresas/${id}`);
  return { success: true as const };
}

// El trigger corta si la empresa participa en alguna obra activa — incluidas
// las que quien desactiva no puede ver. El mensaje viene de la base.
export async function desactivarEmpresa(id: string) {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_empresas")
    .update({ activo: false }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/obras/empresas");
  return { success: true as const };
}

export async function crearPersona(input: CrearPersonaForm) {
  const parsed = crearPersonaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_personas")
    .insert({ ...parsed.data, creado_por: await usuarioActualId() })
    .select("id, pendiente")
    .single();

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/obras/personas");
  revalidatePath("/obras/pendientes");
  return { success: true as const, id: data.id, pendiente: data.pendiente };
}

export async function editarPersona(input: EditarPersonaForm) {
  const parsed = editarPersonaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, ...campos } = parsed.data;

  const { error, count } = await supabase
    .from("obras_personas")
    .update(campos, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/obras/personas");
  revalidatePath(`/obras/personas/${id}`);
  return { success: true as const };
}

export async function desactivarPersona(id: string) {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_personas")
    .update({ activo: false }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/obras/personas");
  return { success: true as const };
}

// El vínculo de la empresa y los de su gente se escriben juntos o no se
// escriben: media empresa vinculada no es un estado que valga la pena poder
// alcanzar. La función devuelve además cuántas personas quedaron esperando
// autorización — sin ese dato, "3 personas vinculadas" mentiría.
export async function vincularEmpresa(input: VincularEmpresaForm) {
  const parsed = vincularEmpresaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const d = parsed.data;

  const { data, error } = await supabase.rpc(
    "obras_vincular_empresa",
    argsRpc<"obras_vincular_empresa">({
      p_obra_id: d.obra_id,
      p_empresa_id: d.empresa_id,
      p_roles: d.roles,
      p_observaciones: d.observaciones ?? null,
      p_personas: d.personas,
    }),
  );

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidarObras(d.obra_id);
  revalidatePath("/obras/pendientes");

  const fila = data?.[0];
  return {
    success: true as const,
    pendiente: fila?.vinculo_pendiente ?? false,
    personas: fila?.personas_agregadas ?? 0,
    personasPendientes: fila?.personas_pendientes ?? 0,
  };
}

export async function editarVinculoEmpresa(id: string, input: VincularEmpresaForm) {
  const parsed = vincularEmpresaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_obra_empresa")
    .update({ roles: parsed.data.roles, observaciones: parsed.data.observaciones }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidarObras(parsed.data.obra_id);
  return { success: true as const };
}

export async function desvincularEmpresa(id: string, obraId: string) {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_obra_empresa")
    .update({ activo: false }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidarObras(obraId);
  return { success: true as const };
}

export async function vincularPersona(input: VincularPersonaForm) {
  const parsed = vincularPersonaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  // Bajo model A no se vincula lo que no se ve: el WITH CHECK de la policy lo
  // rechaza. `mensajeError` traduce el 42501 a algo legible.
  const { error } = await supabase.from("obras_obra_persona").insert(parsed.data);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidarObras(parsed.data.obra_id);
  return { success: true as const };
}

export async function editarVinculoPersona(id: string, input: VincularPersonaForm) {
  const parsed = vincularPersonaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_obra_persona")
    .update(
      {
        roles: parsed.data.roles,
        empresa_id: parsed.data.empresa_id,
        observaciones: parsed.data.observaciones,
      },
      { count: "exact" },
    )
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidarObras(parsed.data.obra_id);
  return { success: true as const };
}

export async function desvincularPersona(id: string, obraId: string) {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_obra_persona")
    .update({ activo: false }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidarObras(obraId);
  return { success: true as const };
}

export async function vincularPersonaEmpresa(input: VincularPersonaEmpresaForm) {
  const parsed = vincularPersonaEmpresaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error } = await supabase.from("obras_persona_empresa").insert(parsed.data);
  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath(`/obras/personas/${parsed.data.persona_id}`);
  revalidatePath(`/obras/empresas/${parsed.data.empresa_id}`);
  return { success: true as const };
}

export async function desvincularPersonaEmpresa(id: string, personaId: string) {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_persona_empresa")
    .update({ activo: false }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidatePath(`/obras/personas/${personaId}`);
  return { success: true as const };
}

// Alta y edición en una: la relación es única por (obra, persona), así que
// "cambiar la comisión" y "marcarlo referente" son la misma escritura.
export async function guardarReferente(input: ReferenteForm) {
  const parsed = referenteSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const d = parsed.data;

  // Un solo statement: el ON CONFLICT de la función decide entre alta y
  // cambio de comisión contra el unique parcial, sin el SELECT previo que
  // dejaba la decisión en TypeScript y en otra transacción.
  const { error } = await supabase.rpc(
    "obras_guardar_referente",
    argsRpc<"obras_guardar_referente">({
      p_obra_id: d.obra_id,
      p_persona_id: d.persona_id,
      p_porcentaje_comision: d.porcentaje_comision,
      p_observaciones: d.observaciones ?? null,
    }),
  );

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidarObras(d.obra_id);
  return { success: true as const };
}

export async function quitarReferente(id: string, obraId: string) {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("obras_obra_referente")
    .update({ activo: false }, { count: "exact" })
    .eq("id", id);

  const fallo = errorDeUpdate({ error, count });
  if (fallo) return { success: false as const, error: fallo };

  revalidarObras(obraId);
  return { success: true as const };
}

// Los tres buscadores son lecturas, pero viven acá porque los llama el
// formulario antes de guardar — un componente cliente no puede importar
// queries.ts.
export async function buscarDuplicadosObra(
  nombre: string,
  direccion?: string,
  localidad?: string,
  excluirId?: string,
): Promise<DuplicadoObra[]> {
  if (!nombre.trim()) return [];

  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_buscar_duplicados_obra", {
    p_nombre: nombre,
    ...(direccion ? { p_direccion: direccion } : {}),
    ...(localidad ? { p_localidad: localidad } : {}),
    ...(excluirId ? { p_excluir_id: excluirId } : {}),
  });

  if (error) return [];
  return (data ?? []) as DuplicadoObra[];
}

export async function buscarDuplicadosEmpresa(
  razonSocial: string,
  nombreComercial?: string,
  excluirId?: string,
): Promise<DuplicadoEmpresa[]> {
  if (!razonSocial.trim()) return [];

  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_buscar_duplicados_empresa", {
    p_razon_social: razonSocial,
    ...(nombreComercial ? { p_nombre_comercial: nombreComercial } : {}),
    ...(excluirId ? { p_excluir_id: excluirId } : {}),
  });

  if (error) return [];
  return (data ?? []) as DuplicadoEmpresa[];
}

export async function buscarDuplicadosPersona(
  nombre: string,
  apellido?: string,
  email?: string,
  telefono?: string,
  excluirId?: string,
): Promise<DuplicadoPersona[]> {
  if (!nombre.trim()) return [];

  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_buscar_duplicados_persona", {
    p_nombre: nombre,
    ...(apellido ? { p_apellido: apellido } : {}),
    ...(email ? { p_email: email } : {}),
    ...(telefono ? { p_telefono: telefono } : {}),
    ...(excluirId ? { p_excluir_id: excluirId } : {}),
  });

  if (error) return [];
  return (data ?? []) as DuplicadoPersona[];
}

// ── Autorizaciones ───────────────────────────────────────────

export async function resolverPendiente(input: ResolverPendienteForm) {
  const parsed = resolverPendienteSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const d = parsed.data;

  const { error } = await supabase.rpc(
    "obras_resolver_pendiente",
    argsRpc<"obras_resolver_pendiente">({
      p_tipo: d.tipo,
      p_id: d.registro_id,
      p_aprobar: d.aprobar,
      p_motivo: d.motivo ?? null,
    }),
  );

  if (error) return { success: false as const, error: mensajeError(error) };

  // Resolver cambia lo que ven las cuatro pantallas, no solo la cola: la fila
  // estaba congelada justamente para todas ellas.
  revalidatePath("/obras/pendientes");
  revalidarObras();
  revalidatePath("/obras/empresas");
  revalidatePath("/obras/personas");
  return { success: true as const };
}

// Contra qué se parece la fila que está esperando. La base solo se lo contesta
// a quien tiene `obras_aprobar`: es la única pantalla del módulo que muestra
// el nombre de una obra ajena.
export async function similaresDelPendiente(
  tipo: TipoPendiente,
  registroId: string,
): Promise<SimilarPendiente[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_pendiente_similares", {
    p_tipo: tipo,
    p_id: registroId,
  });

  if (error) return [];
  return (data ?? []) as SimilarPendiente[];
}

// ── Buscador global ──────────────────────────────────────────
//
// Una llamada para las tres entidades. El alcance no se decide acá: obras y
// empresas pasan por RLS —`obras_buscar` es INVOKER— y las personas fuera de
// alcance vuelven con identidad mínima y `visible = false`. Buscar no abre
// ninguna ficha, así que no escribe en `obras_accesos_persona`.
export async function buscarGlobal(texto: string): Promise<ResultadoBusqueda[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_buscar", { p_texto: texto });

  if (error) return [];
  return (data ?? []) as ResultadoBusqueda[];
}

// ── Buscadores de los paneles de vinculación ─────────────────
//
// Los tres devuelven la misma forma para que los coma el mismo <Buscador />, y
// son actions porque los llama un componente cliente.

export async function buscarEmpresasParaVincular(texto: string) {
  const empresas = await getEmpresas(texto.trim() || undefined);

  // La empresa congelada no se ofrece: vincularla termina en OB012.
  return empresas
    .filter((e) => !e.pendiente)
    .slice(0, 20)
    .map((e) => ({
      id: e.id,
      etiqueta: e.razon_social,
      detalle: [e.nombre_comercial, e.localidad].filter(Boolean).join(" · ") || null,
    }));
}

// Solo obras propias y no congeladas: son las únicas a las que la RLS deja
// colgarle un vínculo.
export async function buscarObrasParaVincular(texto: string) {
  const supabase = await createClient();

  let query = supabase
    .from("obras")
    .select("id, nombre, localidad")
    .eq("activo", true)
    .eq("pendiente", false)
    .eq("responsable_id", await usuarioActualId())
    .order("updated_at", { ascending: false })
    .limit(20);

  if (texto.trim()) query = query.ilike("nombre", `%${texto.trim()}%`);

  const { data, error } = await query;
  if (error) return [];

  return (data ?? []).map((o) => ({ id: o.id, etiqueta: o.nombre, detalle: o.localidad }));
}

// La gente de una empresa, para tildar al vincularla a una obra. Identidad
// mínima otra vez: nombre, apellido y cargo, nunca contacto.
export async function personasDeEmpresa(
  empresaId: string,
  obraId: string,
): Promise<PersonaDeEmpresa[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_personas_de_empresa", {
    p_empresa_id: empresaId,
    p_obra_id: obraId,
  });

  if (error) return [];
  return (data ?? []) as PersonaDeEmpresa[];
}
