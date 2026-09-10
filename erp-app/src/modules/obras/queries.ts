import { createClient } from "@/lib/supabase/server";
import { getUsuariosActivos, getUsuarioActualId } from "@/lib/usuarios";
import {
  puedeTransferir,
  puedeVerTodasLasEmpresas,
  puedeVerTodasLasPersonas,
} from "./permissions";
import type {
  AccesoAuditoria,
  Alcance,
  Compartido,
  CompartidoRow,
  ContactoExclusivo,
  Empresa,
  FiltrosObras,
  HistorialAprobacion,
  Obra,
  ObraListado,
  Pendiente,
  PersonaListado,
  RelacionCompartible,
  TransferenciaAuditoria,
  Usuario,
} from "./types";

export { getUsuarioActualId } from "@/lib/usuarios";

// El destino de una transferencia tiene que tener `obras_ver`, pero eso vive en
// usuario_submodulos y no es legible desde acá. La validación real está en
// obras_transferir(), que rechaza el destino sin acceso con un mensaje claro.
export function getUsuariosParaTransferir(): Promise<Usuario[]> {
  return getUsuariosActivos();
}

// RLS ya acota a lo del usuario (o a todo, con el permiso `_todas` /
// `obras_transferir`). `alcance` es una comodidad de UI: por default el listado
// muestra lo propio incluso a quien puede ver todo; sube a "todos" solo si lo
// pide y el permiso lo respalda.
export async function getObras(filtros: FiltrosObras = {}): Promise<ObraListado[]> {
  const supabase = await createClient();

  const idsPorRelacion = await obraIdsPorRelacion(filtros);
  if (idsPorRelacion?.length === 0) return [];

  let query = supabase
    .from("obras")
    .select(
      "*, responsable:usuarios(id, nombre), obras_obra_empresa(id), obras_obra_persona(id)",
    )
    .eq("activo", true)
    .eq("obras_obra_empresa.activo", true)
    .eq("obras_obra_persona.activo", true)
    .order("updated_at", { ascending: false });

  const verTodos = filtros.alcance === "todos" && (await puedeTransferir());
  if (!verTodos) {
    const me = await getUsuarioActualId();
    if (!me) return [];
    // Por default el listado muestra lo propio + lo que me compartieron (la RLS
    // ya deja ver ambas; esto es solo el recorte de UI).
    const compartidas = await obraIdsCompartidasConmigo(me);
    query = compartidas.length
      ? query.or(`responsable_id.eq.${me},id.in.(${compartidas.join(",")})`)
      : query.eq("responsable_id", me);
  }

  if (filtros.nombre) query = query.ilike("nombre", `%${filtros.nombre}%`);
  if (filtros.estado) query = query.eq("estado", filtros.estado);
  if (filtros.tipo) query = query.eq("tipo", filtros.tipo);
  if (filtros.localidad) query = query.ilike("localidad", `%${filtros.localidad}%`);
  if (idsPorRelacion) query = query.in("id", idsPorRelacion);

  const { data, error } = await query;
  if (error) throw error;

  const obras = (data ?? []).map((o) => {
    const { obras_obra_empresa, obras_obra_persona, responsable, ...obra } = o;
    return {
      ...(obra as Obra),
      responsable: responsable as Usuario | null,
      empresas: obras_obra_empresa.length,
      personas: obras_obra_persona.length,
    };
  });

  // El filtro "responsable inactivo" no se puede expresar en la query: la
  // policy de usuarios no expone `activo`, así que el embed no lo trae. Se
  // resuelve con la lista de activos, que ya se pide para el picker.
  if (!filtros.responsable_inactivo) return obras;

  const activos = new Set((await getUsuariosActivos()).map((u) => u.id));
  return obras.filter((o) => !activos.has(o.responsable_id));
}

// Filtrar por empresa o persona relacionada pide un paso previo: PostgREST
// mezclaría el !inner con los embeds que se usan para contar.
async function obraIdsPorRelacion(filtros: FiltrosObras): Promise<string[] | null> {
  if (!filtros.empresa_id && !filtros.persona_id) return null;

  const supabase = await createClient();
  const listas: string[][] = [];

  if (filtros.empresa_id) {
    const { data, error } = await supabase
      .from("obras_obra_empresa")
      .select("obra_id")
      .eq("empresa_id", filtros.empresa_id)
      .eq("activo", true);
    if (error) throw error;
    listas.push((data ?? []).map((r) => r.obra_id));
  }

  if (filtros.persona_id) {
    const { data, error } = await supabase
      .from("obras_obra_persona")
      .select("obra_id")
      .eq("persona_id", filtros.persona_id)
      .eq("activo", true);
    if (error) throw error;
    listas.push((data ?? []).map((r) => r.obra_id));
  }

  return listas.reduce((a, b) => a.filter((id) => b.includes(id)));
}

async function obraIdsCompartidasConmigo(me: string): Promise<string[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("obras_obra_compartida")
    .select("obra_id")
    .eq("usuario_id", me)
    .eq("activo", true);
  if (error) throw error;
  return (data ?? []).map((r) => r.obra_id);
}

export async function getObra(id: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras")
    .select("*, responsable:usuarios(id, nombre)")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Los vínculos de la ficha por función y no por embed: la empresa/persona que
// sumó un receptor de la obra compartida es privada de ese receptor, así que
// el embed la traería en NULL. `obras_vinculos_de_obra` resuelve el nombre
// (identidad mínima) y marca quién lo agregó.
export async function getVinculosObra(obraId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_vinculos_de_obra", { p_obra_id: obraId });
  if (error) throw error;
  return data ?? [];
}

// Separado de getObra: la fila trae la comisión, así que la policy exige
// `obras_referentes`. Pedirla en el mismo select le devolvería un array vacío
// a quien no tiene el permiso, indistinguible de "no hay referentes".
export async function getReferentes(obraId: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_obra_referente")
    .select("id, persona_id, porcentaje_comision, observaciones, obras_personas(id, nombre, apellido)")
    .eq("obra_id", obraId)
    .eq("activo", true);

  if (error) throw error;
  return data ?? [];
}

export async function getTransferencias(obraId: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_transferencias")
    .select("id, created_at, de:de_usuario_id(nombre), a:a_usuario_id(nombre)")
    .eq("obra_id", obraId)
    .eq("tipo", "obra")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

export async function getEmpresas(busqueda?: string, alcance?: Alcance): Promise<Empresa[]> {
  const supabase = await createClient();

  let query = supabase
    .from("obras_empresas")
    .select("*")
    .eq("activo", true)
    .order("razon_social");

  const verTodos = alcance === "todos" && (await puedeVerTodasLasEmpresas());
  if (!verTodos) {
    const me = await getUsuarioActualId();
    if (!me) return [];
    query = query.eq("creado_por", me);
  }

  if (busqueda) query = query.ilike("razon_social", `%${busqueda}%`);

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

export async function getEmpresa(id: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_empresas")
    .select(
      `*,
       obras_persona_empresa(id, cargo, es_principal, obras_personas(id, nombre, apellido)),
       obras_obra_empresa(id, roles, obras(id, nombre, estado, localidad))`,
    )
    .eq("id", id)
    .eq("obras_persona_empresa.activo", true)
    .eq("obras_obra_empresa.activo", true)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Solo las personas al alcance del usuario: RLS filtra por creación propia,
// grant o `obras_personas_todas`. El listado nunca trae contacto — desde
// sql/039 `telefono`/`whatsapp`/`email` no tienen GRANT SELECT y un `select("*")`
// daría 403. El contacto sale solo por `getFichaPersona`.
export async function getPersonas(busqueda?: string, alcance?: Alcance): Promise<PersonaListado[]> {
  const supabase = await createClient();

  let query = supabase
    .from("obras_personas")
    .select(
      "id, nombre, apellido, nombre_norm, observaciones, creado_por, activo, pendiente, motivo_rechazo, created_at, updated_at",
    )
    .eq("activo", true)
    .order("apellido", { nullsFirst: false })
    .order("nombre");

  const verTodos = alcance === "todos" && (await puedeVerTodasLasPersonas());
  if (!verTodos) {
    const me = await getUsuarioActualId();
    if (!me) return [];
    query = query.eq("creado_por", me);
  }

  if (busqueda) query = query.ilike("nombre_norm", `%${busqueda.toLowerCase()}%`);

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

// Único camino a teléfono, whatsapp y email. Cada llamada queda registrada en
// obras_accesos_persona — por eso no se reemplaza por un select directo. Con
// `ctx` (obra o empresa) autoriza por grant contextual: el contacto se ve solo
// desde esa ficha.
export async function getFichaPersona(
  id: string,
  ctx?: { tipo: "obra" | "empresa"; id: string },
) {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_ficha_persona", {
    p_persona_id: id,
    ...(ctx ? { p_ctx_tipo: ctx.tipo, p_ctx_id: ctx.id } : {}),
  });
  if (error) throw error;
  return data?.[0] ?? null;
}

// `obras_ficha_persona` devuelve contacto y nada más — el estado de
// autorización no entra en su firma. Este select lo trae aparte, y sirve
// además para la persona rechazada: su fila queda desactivada, así que la
// función ya no la devuelve y sin esto quien la cargó vería un 404 en vez del
// motivo.
export async function getEstadoPersona(id: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_personas")
    .select("id, nombre, apellido, activo, pendiente, motivo_rechazo, creado_por")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

export async function getVinculosPersona(id: string) {
  const supabase = await createClient();

  const [{ data: empresas, error: errorEmpresas }, { data: obras, error: errorObras }] =
    await Promise.all([
      supabase
        .from("obras_persona_empresa")
        .select("id, cargo, es_principal, obras_empresas(id, razon_social)")
        .eq("persona_id", id)
        .eq("activo", true),
      supabase
        .from("obras_obra_persona")
        .select("id, roles, obras(id, nombre, estado), obras_empresas(id, razon_social)")
        .eq("persona_id", id)
        .eq("activo", true),
    ]);

  if (errorEmpresas) throw errorEmpresas;
  if (errorObras) throw errorObras;

  return { empresas: empresas ?? [], obras: obras ?? [] };
}

// Las comisiones de una persona, por obra. RLS ya exige `obras_referentes` y
// que la obra sea visible: sin el permiso vuelve vacío, que es lo correcto.
export async function getReferenciasDePersona(personaId: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_obra_referente")
    .select("obra_id, porcentaje_comision")
    .eq("persona_id", personaId)
    .eq("activo", true);

  if (error) throw error;
  return data ?? [];
}

// Con quién está compartida una ficha. Solo lo ve el dueño (RLS de
// obras_persona_compartida / _empresa).
export async function getCompartidosPersona(personaId: string): Promise<Compartido[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_persona_compartida")
    .select("usuario_id, created_at, usuario:usuario_id(nombre)")
    .eq("persona_id", personaId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data ?? []).map((r) => ({
    usuario_id: r.usuario_id,
    usuario: (r.usuario as { nombre: string } | null)?.nombre ?? "—",
    created_at: r.created_at,
  }));
}

export async function getCompartidosEmpresa(empresaId: string): Promise<Compartido[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_empresa_compartida")
    .select("usuario_id, created_at, usuario:usuario_id(nombre)")
    .eq("empresa_id", empresaId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data ?? []).map((r) => ({
    usuario_id: r.usuario_id,
    usuario: (r.usuario as { nombre: string } | null)?.nombre ?? "—",
    created_at: r.created_at,
  }));
}

export async function getCompartidosObra(obraId: string): Promise<Compartido[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras_obra_compartida")
    .select("usuario_id, created_at, usuario:usuario_id(nombre)")
    .eq("obra_id", obraId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data ?? []).map((r) => ({
    usuario_id: r.usuario_id,
    usuario: (r.usuario as { nombre: string } | null)?.nombre ?? "—",
    created_at: r.created_at ?? "",
  }));
}

// Todo lo que compartí, para la vista Compartido. Por función: los JOIN a
// obras/empresas/personas/usuarios tienen que resolver aunque no vea alguna
// fila por RLS.
export async function getCompartidosPorMi(): Promise<CompartidoRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_compartidos_por_mi");
  if (error) throw error;
  return (data ?? []) as CompartidoRow[];
}

// Lo vinculado solo a esta obra/empresa que el dueño saliente posee: el
// checklist de confirmación de la transferencia.
export async function getContactosExclusivosObra(obraId: string): Promise<ContactoExclusivo[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_contactos_exclusivos_de_obra", {
    p_obra_id: obraId,
  });
  if (error) throw error;
  return (data ?? []) as ContactoExclusivo[];
}

export async function getContactosExclusivosEmpresa(
  empresaId: string,
): Promise<ContactoExclusivo[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_contactos_exclusivos_de_empresa", {
    p_empresa_id: empresaId,
  });
  if (error) throw error;
  return (data ?? []) as ContactoExclusivo[];
}

// Lo vinculado que es mío y puedo compartir junto con la obra/empresa. Depende
// del usuario destino: marca lo que ya tiene.
export async function getRelacionesCompartiblesObra(
  obraId: string,
  usuarioId: string,
): Promise<RelacionCompartible[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_relaciones_compartibles_obra", {
    p_obra_id: obraId,
    p_usuario_id: usuarioId,
  });
  if (error) throw error;
  return (data ?? []) as RelacionCompartible[];
}

export async function getRelacionesCompartiblesEmpresa(
  empresaId: string,
  usuarioId: string,
): Promise<RelacionCompartible[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_relaciones_compartibles_empresa", {
    p_empresa_id: empresaId,
    p_usuario_id: usuarioId,
  });
  if (error) throw error;
  return (data ?? []) as RelacionCompartible[];
}

// Los dos logs de la vista de Auditoría. Van por función y no por select
// directo: `obras_accesos_persona` solo la ve quien tiene
// `obras_personas_todas`, y las transferencias solo quien ve la obra — con un
// embed, un auditor sin esos permisos recibiría filas con todo en NULL. La
// función verifica `obras_auditoria` y sirve nombres, nunca contacto.
export async function getAuditoriaAccesos(dias: number) {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_auditoria_accesos", { p_dias: dias });
  if (error) throw error;
  return (data ?? []) as AccesoAuditoria[];
}

export async function getAuditoriaTransferencias(dias: number) {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_auditoria_transferencias", { p_dias: dias });
  if (error) throw error;
  return (data ?? []) as TransferenciaAuditoria[];
}

// La cola de autorizaciones y su historial. Van por función por lo mismo que
// la auditoría: quien aprueba necesita ver las tres tablas de alta enteras y no
// tiene por qué tener permiso sobre la agenda ni sobre las obras ajenas.
export async function getPendientes(): Promise<Pendiente[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_pendientes");
  if (error) throw error;
  return (data ?? []) as Pendiente[];
}

export async function getHistorialAprobaciones(dias: number): Promise<HistorialAprobacion[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_historial_aprobaciones", { p_dias: dias });
  if (error) throw error;
  return (data ?? []) as HistorialAprobacion[];
}
