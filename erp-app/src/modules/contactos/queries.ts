import type { UsuarioBasico } from "@/lib/usuarios";
import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";
import {
  COLUMNAS_PERSONA,
  type Edicion,
  type Empresa,
  type Guardado,
  type Parecida,
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

// Las de su equipo (sin equipo, las que cargó) y las compartidas con él; el
// admin, todas.
export async function getEmpresas({ todas, yo }: { todas: boolean; yo: string }): Promise<(Empresa & { compartida: boolean })[]> {
  const supabase = await createClient();
  let query = supabase.from("contactos_empresas").select("*").order("nombre");
  let compartidas = new Set<string>();
  if (!todas) {
    const { data: equipo, error } = await supabase.rpc("mi_equipo");
    if (error) throw error;
    if (equipo) {
      const { data, error } = await supabase
        .from("contactos_empresa_equipos")
        .select("empresa_id")
        .eq("equipo_id", equipo);
      if (error) throw error;
      compartidas = new Set(data.map((c) => c.empresa_id));
    }
    const propias = equipo ? `equipo_id.eq.${equipo}` : `and(equipo_id.is.null,creado_por.eq.${yo})`;
    query = query
      .eq("activo", true)
      .or(compartidas.size > 0 ? `${propias},id.in.(${[...compartidas].join(",")})` : propias);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data.map((e) => ({ ...e, compartida: compartidas.has(e.id) }));
}

// Con qué equipos se compartió (se ve con la empresa) y los equipos activos,
// para compartir o para que el admin la pase (CO008): `contactos_equipos`,
// porque el vendedor no lee `equipos`.
export async function getCompartida(empresa: string) {
  const supabase = await createClient();
  const [filas, equipos] = await Promise.all([
    supabase.from("contactos_empresa_equipos").select("equipo_id, created_at").eq("empresa_id", empresa).order("created_at"),
    supabase.rpc("contactos_equipos"),
  ]);
  for (const r of [filas, equipos]) if (r.error) throw r.error;
  return { compartidaCon: filas.data ?? [], equipos: equipos.data ?? [] };
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

type FilaPorAprobar = Database["public"]["Functions"]["contactos_por_aprobar"]["Returns"][number];
export type PorAprobar = Omit<FilaPorAprobar, "tipo" | "equipo" | "antes" | "parecidas" | "guardados"> & {
  tipo: "persona" | "empresa";
  equipo: string | null;
  antes: { nombre: string } | null;
  parecidas: Parecida[];
  guardados: Guardado[];
};

// Vacía sin `contactos_aprobar`: la función lo decide.
export async function getPorAprobar(): Promise<PorAprobar[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_por_aprobar");
  if (error) throw error;
  return data.map((f) => ({
    ...f,
    tipo: f.tipo as PorAprobar["tipo"],
    equipo: f.equipo as string | null,
    antes: f.antes as PorAprobar["antes"],
    parecidas: f.parecidas as Parecida[],
    guardados: f.guardados as Guardado[],
  }));
}

// Auditoría: vacías sin `contactos_auditoria`, la función lo decide.
export async function getAuditoriaResumen(dias: number) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_auditoria_resumen", { p_dias: dias });
  if (error) throw error;
  return data;
}

export type AccesoAuditado = Database["public"]["Functions"]["contactos_auditoria_detalle"]["Returns"][number];

// Hasta 501 filas: si llega la 501, hay más de las 500 que se muestran.
export async function getAuditoriaDetalle(dias: number, usuario: string | null, persona: string | null) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_auditoria_detalle", {
    p_dias: dias,
    p_usuario: usuario ?? undefined,
    p_persona: persona ?? undefined,
  });
  if (error) throw error;
  return data;
}
