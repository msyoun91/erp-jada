import type { UsuarioBasico } from "@/lib/usuarios";
import { createClient } from "@/lib/supabase/server";
import {
  COLUMNAS_PERSONA,
  type Edicion,
  type Empresa,
  type Persona,
  type PersonaEmpresa,
  type Vinculo,
} from "./types";

// id de usuario o equipo → nombre, de lo que se ve (`contactos_nombres`, sql/130).
export async function getNombres(): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_nombres");
  if (error) throw error;
  return Object.fromEntries(data.map((n) => [n.id, n.nombre]));
}

// A quién se transfiere una persona: los activos con `contactos_ver`.
export async function getCandidatos(): Promise<UsuarioBasico[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("usuarios_con_permiso", { p_codigo: "contactos_ver" });
  if (error) throw error;
  return data;
}

// A qué equipo pasa una empresa (CO008, solo el admin): los activos que deja
// ver la RLS de `equipos`.
export async function getEquipos(): Promise<{ id: string; nombre: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("equipos").select("id, nombre").eq("activo", true).order("nombre");
  if (error) throw error;
  return data;
}

// La agenda: las personas de las que es dueño. Las que ve en contexto (por una
// obra) aparecen en la obra, no acá. El admin ve todas, también las desactivadas.
export async function getPersonas({ todas, yo }: { todas: boolean; yo: string }): Promise<Persona[]> {
  const supabase = await createClient();
  let query = supabase.from("contactos_personas").select(COLUMNAS_PERSONA).order("nombre");
  if (!todas) query = query.eq("responsable_id", yo).eq("activo", true);
  const { data, error } = await query;
  if (error) throw error;
  return data;
}

// Las de su equipo (sin equipo, las que cargó); el admin, todas.
export async function getEmpresas({ todas, yo }: { todas: boolean; yo: string }): Promise<Empresa[]> {
  const supabase = await createClient();
  let query = supabase.from("contactos_empresas").select("*").order("nombre");
  if (!todas) {
    const { data: equipo, error } = await supabase.rpc("mi_equipo");
    if (error) throw error;
    query = query
      .eq("activo", true)
      .or(equipo ? `equipo_id.eq.${equipo}` : `and(equipo_id.is.null,creado_por.eq.${yo})`);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data;
}

// Un vínculo con el registro al que apunta, resuelto como lo ve quien lee:
// sin etiqueta (no lo ve), sin link.
export type VinculoConRegistro = Vinculo & { etiqueta: string | null; href: string | null };

async function conRegistro(vinculos: Vinculo[]): Promise<VinculoConRegistro[]> {
  if (vinculos.length === 0) return [];
  const supabase = await createClient();
  const { data: entes, error } = await supabase.from("entes").select("codigo, ruta");
  if (error) throw error;
  const rutas = new Map(entes.map((e) => [e.codigo, e.ruta]));
  return Promise.all(
    vinculos.map(async (v) => {
      const { data: etiqueta, error } = await supabase.rpc("etiqueta_registro", {
        p_ente: v.ente,
        p_id: v.registro_id,
      });
      if (error) throw error;
      const ruta = rutas.get(v.ente);
      return { ...v, etiqueta, href: etiqueta !== null && ruta ? ruta.replace("{id}", v.registro_id) : null };
    })
  );
}

export type PersonaEmpresaConNombre = PersonaEmpresa & {
  contactos_empresas: Pick<Empresa, "id" | "nombre"> | null;
};

export type PersonaCompleta = {
  persona: Persona;
  empresas: PersonaEmpresaConNombre[];
  vinculos: VinculoConRegistro[];
  ediciones: Edicion[];
};

// Lo que no se ve lo recorta la RLS: sin persona visible, null. La empresa de
// una relación llega null si quien lee no la ve.
export async function getPersona(id: string): Promise<PersonaCompleta | null> {
  const supabase = await createClient();
  const [persona, empresas, vinculos, ediciones] = await Promise.all([
    supabase.from("contactos_personas").select(COLUMNAS_PERSONA).eq("id", id).maybeSingle(),
    supabase
      .from("contactos_persona_empresa")
      .select("*, contactos_empresas(id, nombre)")
      .eq("persona_id", id)
      .eq("activo", true)
      .order("desde", { ascending: false }),
    supabase.from("contactos_vinculos").select("*").eq("persona_id", id).eq("activo", true).order("desde"),
    supabase.from("contactos_ediciones").select("*").eq("persona_id", id).order("created_at"),
  ]);
  for (const r of [persona, empresas, vinculos, ediciones]) if (r.error) throw r.error;
  if (!persona.data) return null;
  return {
    persona: persona.data,
    empresas: empresas.data ?? [],
    vinculos: await conRegistro(vinculos.data ?? []),
    ediciones: ediciones.data ?? [],
  };
}

export type EmpleadoConNombre = PersonaEmpresa & {
  contactos_personas: Pick<Persona, "id" | "nombre" | "responsable_id"> | null;
};

export type EmpresaCompleta = {
  empresa: Empresa;
  personas: EmpleadoConNombre[];
  vinculos: VinculoConRegistro[];
  ediciones: Edicion[];
};

export async function getEmpresa(id: string): Promise<EmpresaCompleta | null> {
  const supabase = await createClient();
  const [empresa, personas, vinculos, ediciones] = await Promise.all([
    supabase.from("contactos_empresas").select("*").eq("id", id).maybeSingle(),
    supabase
      .from("contactos_persona_empresa")
      .select("*, contactos_personas(id, nombre, responsable_id)")
      .eq("empresa_id", id)
      .eq("activo", true)
      .order("desde", { ascending: false }),
    supabase.from("contactos_vinculos").select("*").eq("empresa_id", id).eq("activo", true).order("desde"),
    supabase.from("contactos_ediciones").select("*").eq("empresa_id", id).order("created_at"),
  ]);
  for (const r of [empresa, personas, vinculos, ediciones]) if (r.error) throw r.error;
  if (!empresa.data) return null;
  return {
    empresa: empresa.data,
    // La RLS de la relación es la de la persona: la que no se ve no llega.
    personas: personas.data ?? [],
    vinculos: await conRegistro(vinculos.data ?? []),
    ediciones: ediciones.data ?? [],
  };
}

export type VinculoDeRegistro = Vinculo & {
  contactos_personas: Pick<Persona, "id" | "nombre" | "activo"> | null;
  contactos_empresas: Pick<Empresa, "id" | "nombre" | "activo"> | null;
};

// Los contactos de un registro de otro módulo (la obra), abiertos y cerrados:
// la sección que la ficha compone desde `app/`.
export async function getVinculosDe(ente: string, registro: string): Promise<VinculoDeRegistro[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("contactos_vinculos")
    .select("*, contactos_personas(id, nombre, activo), contactos_empresas(id, nombre, activo)")
    .eq("ente", ente)
    .eq("registro_id", registro)
    .eq("activo", true)
    .order("desde");
  if (error) throw error;
  return data;
}
