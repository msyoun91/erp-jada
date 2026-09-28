import type { UsuarioBasico } from "@/lib/usuarios";
import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";
import type { Comision, Guardado, Obra, Parecida, Participante } from "./types";

export type Evento = Database["public"]["Tables"]["eventos"]["Row"];

// id de usuario → nombre, de lo que se ve (`obras_nombres`, sql/130).
export async function getNombres(): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_nombres");
  if (error) throw error;
  return Object.fromEntries(data.map((n) => [n.id, n.nombre]));
}

// A quién se transfiere o se suma: los activos con `obras_ver`.
export async function getCandidatos(): Promise<UsuarioBasico[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("usuarios_con_permiso", { p_codigo: "obras_ver" });
  if (error) throw error;
  return data;
}

export type ObraResumen = Pick<
  Obra,
  "id" | "nombre" | "direccion" | "localidad" | "estado" | "responsable_id" | "activo" | "congelada" | "updated_at"
>;

const RESUMEN = "id, nombre, direccion, localidad, estado, responsable_id, activo, congelada, updated_at";

// La RLS decide cuáles: las del vendedor, las de su equipo al jefe, todas al
// admin. Obras muestra las activas; Todas, también las desactivadas.
export async function getObras({ inactivas }: { inactivas: boolean }): Promise<ObraResumen[]> {
  const supabase = await createClient();
  let query = supabase.from("obras").select(RESUMEN).order("updated_at", { ascending: false });
  if (!inactivas) query = query.eq("activo", true);
  const { data, error } = await query;
  if (error) throw error;
  return data;
}

export type ObraCompleta = {
  obra: Obra;
  participantes: Participante[];
  historial: Evento[];
  trabaja: boolean;
  aCargo: boolean;
};

// Lo que no se ve lo recorta la RLS: sin obra visible, null.
export async function getObra(id: string): Promise<ObraCompleta | null> {
  const supabase = await createClient();
  const [obra, participantes, historial, trabaja, aCargo] = await Promise.all([
    supabase.from("obras").select("*").eq("id", id).maybeSingle(),
    supabase.from("obras_participantes").select("*").eq("obra_id", id).eq("activo", true).order("created_at"),
    supabase.from("eventos").select("*").eq("ente", "obra").eq("registro_id", id).order("created_at"),
    supabase.rpc("obras_trabaja", { p_obra: id }),
    supabase.rpc("obras_a_cargo", { p_obra: id }),
  ]);
  for (const r of [obra, participantes, historial, trabaja, aCargo]) if (r.error) throw r.error;
  if (!obra.data) return null;
  return {
    obra: obra.data,
    participantes: participantes.data ?? [],
    historial: historial.data ?? [],
    trabaja: trabaja.data ?? false,
    aCargo: aCargo.data ?? false,
  };
}

// Vigentes e historial de los vínculos dados; la RLS deja solo las de quien
// tiene la obra a cargo. Las más nuevas primero.
export async function getComisiones(vinculos: string[]): Promise<Comision[]> {
  if (vinculos.length === 0) return [];
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("obras_comisiones")
    .select("*")
    .in("vinculo_id", vinculos)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export type Numero = Database["public"]["Functions"]["obras_contar"]["Returns"][number];

// Los números del widget: lo que quien llama ve o, con `obras_numeros`, todas.
// La función cuenta; nunca devuelve obras.
export async function getNumeros(dias: number): Promise<Numero[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_contar", { p_dias: dias });
  if (error) throw error;
  return data;
}

type FilaPorAprobar = Database["public"]["Functions"]["obras_por_aprobar"]["Returns"][number];
export type PorAprobar = Omit<FilaPorAprobar, "antes" | "parecidas" | "guardados"> & {
  antes: { nombre: string; direccion: string } | null;
  parecidas: Parecida[];
  guardados: Guardado[];
};

// Vacía sin `obras_aprobar`: la función lo decide.
export async function getPorAprobar(): Promise<PorAprobar[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_por_aprobar");
  if (error) throw error;
  return data.map((f) => ({
    ...f,
    antes: f.antes as PorAprobar["antes"],
    parecidas: f.parecidas as Parecida[],
    guardados: f.guardados as Guardado[],
  }));
}
