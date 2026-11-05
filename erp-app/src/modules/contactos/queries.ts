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

// Quiénes pueden ser dueños, para marcar huérfanas: solo la lista del admin las marca.
async function getPueden(todas: boolean): Promise<Set<string> | null> {
  return todas ? new Set((await getCandidatos()).map((c) => c.id)) : null;
}

// La agenda: las personas de las que es dueño. Las que ve en contexto (por una
// obra) aparecen en la obra, no acá. El admin ve todas, también las desactivadas.
// Huérfana: activa y con un dueño sin `contactos_ver` (`contactos_avisar_huerfanas`).
export async function getPersonas({ todas, yo }: { todas: boolean; yo: string }): Promise<(Persona & { huerfana: boolean })[]> {
  const supabase = await createClient();
  let query = supabase.from("contactos_personas").select(COLUMNAS_PERSONA).order("nombre");
  if (!todas) query = query.eq("responsable_id", yo).eq("activo", true);
  const [{ data, error }, pueden] = await Promise.all([query, getPueden(todas)]);
  if (error) throw error;
  return data.map((p) => ({ ...p, huerfana: pueden !== null && p.activo && !pueden.has(p.responsable_id) }));
}

// Las de su equipo (sin equipo, las que cargó) y las compartidas con él; el
// admin, todas. Las compartidas llegan por su tabla y se juntan acá, no con un
// `id.in.(…)` en la URL, que crece con cada empresa compartida.
async function getEmpresasVisibles(todas: boolean, yo: string): Promise<(Empresa & { compartida: boolean })[]> {
  const supabase = await createClient();
  if (todas) {
    const { data, error } = await supabase.from("contactos_empresas").select("*").order("nombre");
    if (error) throw error;
    return data.map((e) => ({ ...e, compartida: false }));
  }

  const { data: equipo, error } = await supabase.rpc("mi_equipo");
  if (error) throw error;
  const propias = supabase.from("contactos_empresas").select("*").eq("activo", true);
  if (!equipo) {
    const { data, error } = await propias.is("equipo_id", null).eq("creado_por", yo).order("nombre");
    if (error) throw error;
    return data.map((e) => ({ ...e, compartida: false }));
  }

  const [delEquipo, conMiEquipo] = await Promise.all([
    propias.eq("equipo_id", equipo),
    supabase
      .from("contactos_empresa_equipos")
      .select("contactos_empresas!inner(*)")
      .eq("equipo_id", equipo)
      .eq("contactos_empresas.activo", true),
  ]);
  if (delEquipo.error) throw delEquipo.error;
  if (conMiEquipo.error) throw conMiEquipo.error;
  const porId = new Map(delEquipo.data.map((e) => [e.id, { ...e, compartida: false }]));
  for (const { contactos_empresas: e } of conMiEquipo.data) porId.set(e.id, { ...e, compartida: true });
  return [...porId.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}

// Huérfana: activa, sin equipo y con una cargadora sin `contactos_ver`: no la
// ve nadie más que el admin, que le asigna un equipo.
export async function getEmpresas({
  todas,
  yo,
}: {
  todas: boolean;
  yo: string;
}): Promise<(Empresa & { compartida: boolean; huerfana: boolean })[]> {
  const [empresas, pueden] = await Promise.all([getEmpresasVisibles(todas, yo), getPueden(todas)]);
  return empresas.map((e) => ({
    ...e,
    huerfana: pueden !== null && e.activo && e.equipo_id === null && !pueden.has(e.creado_por),
  }));
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

// Un lado de la fusión, igual para persona y empresa. `quien` es el dueño (la
// persona) o el equipo (la empresa; sin equipo, quien la cargó). `contacto`
// llega null en la persona: se lee con "Ver contacto", que registra.
export type LadoFusion = {
  id: string;
  nombre: string;
  quien: string | null;
  equipo: string | null;
  created_at: string;
  vinculos: VinculoConRegistro[];
  relaciones: string[];
  contacto: { telefono: string | null; email: string | null } | null;
};

// Solo activas y aprobadas: lo demás no se fusiona (CO030).
export async function getLadoFusion(tipo: "persona" | "empresa", id: string): Promise<LadoFusion | null> {
  if (tipo === "persona") {
    const d = await getPersona(id);
    if (!d || !d.persona.activo || d.persona.congelada) return null;
    return {
      id,
      nombre: d.persona.nombre,
      quien: d.persona.responsable_id,
      equipo: null,
      created_at: d.persona.created_at,
      vinculos: d.vinculos.filter((v) => v.hasta === null),
      relaciones: d.empresas.flatMap((r) => (r.hasta === null && r.contactos_empresas ? [r.contactos_empresas.nombre] : [])),
      contacto: null,
    };
  }
  const d = await getEmpresa(id);
  if (!d || !d.empresa.activo || d.empresa.congelada) return null;
  return {
    id,
    nombre: d.empresa.nombre,
    quien: d.empresa.equipo_id ?? d.empresa.creado_por,
    equipo: d.empresa.equipo_id,
    created_at: d.empresa.created_at,
    vinculos: d.vinculos.filter((v) => v.hasta === null),
    relaciones: d.personas.flatMap((r) => (r.hasta === null && r.contactos_personas ? [r.contactos_personas.nombre] : [])),
    contacto: { telefono: d.empresa.telefono, email: d.empresa.email },
  };
}

// "Se fusionó con …" (`contactos_fusionada`): el id solo si quien lee ve la que queda.
export type Fusionada = { id: string | null; nombre: string; dueno: string };

export async function getFusionada(tipo: "persona" | "empresa", id: string): Promise<Fusionada | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("contactos_fusionada", { p_tipo: tipo, p_id: id });
  if (error) throw error;
  const f = data[0];
  return f ? { id: f.id as string | null, nombre: f.nombre, dueno: f.dueno } : null;
}
