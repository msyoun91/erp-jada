import { createClient } from "@/lib/supabase/server";
import { getUsuariosActivos } from "@/lib/usuarios";
import type {
  Empresa,
  FiltrosObras,
  Obra,
  ObraListado,
  Persona,
  Usuario,
} from "./types";

export { getUsuarioActualId } from "@/lib/usuarios";

// El destino de una transferencia tiene que tener `obras_ver`, pero eso vive en
// usuario_submodulos y no es legible desde acá. La validación real está en
// obras_transferir(), que rechaza el destino sin acceso con un mensaje claro.
export function getUsuariosParaTransferir(): Promise<Usuario[]> {
  return getUsuariosActivos();
}

// RLS ya acota a las obras del usuario (o a todas, si tiene obras_transferir).
// Acá no se re-implementa visibilidad.
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

export async function getObra(id: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("obras")
    .select(
      `*,
       responsable:usuarios(id, nombre),
       obras_obra_empresa(id, roles, observaciones, obras_empresas(id, razon_social, nombre_comercial)),
       obras_obra_persona(id, roles, observaciones, empresa_id,
         obras_personas(id, nombre, apellido),
         obras_empresas(id, razon_social))`,
    )
    .eq("id", id)
    .eq("obras_obra_empresa.activo", true)
    .eq("obras_obra_persona.activo", true)
    .maybeSingle();

  if (error) throw error;
  return data;
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
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

export async function getEmpresas(busqueda?: string): Promise<Empresa[]> {
  const supabase = await createClient();

  let query = supabase
    .from("obras_empresas")
    .select("*")
    .eq("activo", true)
    .order("razon_social");

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

// Solo las personas al alcance del usuario: RLS filtra por obra propia,
// creación propia o `obras_personas_todas`.
export async function getPersonas(busqueda?: string): Promise<Persona[]> {
  const supabase = await createClient();

  let query = supabase
    .from("obras_personas")
    .select("*")
    .eq("activo", true)
    .order("apellido", { nullsFirst: false })
    .order("nombre");

  if (busqueda) query = query.ilike("nombre_norm", `%${busqueda.toLowerCase()}%`);

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

// Único camino a teléfono, whatsapp y email. Cada llamada queda registrada en
// obras_accesos_persona — por eso no se reemplaza por un select directo.
export async function getFichaPersona(id: string) {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("obras_ficha_persona", { p_persona_id: id });
  if (error) throw error;
  return data?.[0] ?? null;
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
