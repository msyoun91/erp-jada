import { createClient } from "@/lib/supabase/server";
import type {
  Empresa,
  Fuente,
  ObraConRelaciones,
  PersonaConEmpresa,
  ProspectoListado,
} from "./types";

export { getUsuarioActualId, getUsuariosActivos } from "@/lib/usuarios";

// La ficha de la obra y la fila del listado necesitan lo mismo: las relaciones
// con sus roles. Un solo select para las dos vistas — la obra no puede leerse
// distinto según desde dónde se la mire.
// Las filas inactivas vienen incluidas y se filtran al derivar (empresaPrincipal,
// referente): pedir `activo` anidado por PostgREST obliga a un filtro por cada
// nivel y deja fuera la obra entera cuando alguna relación no matchea.
const SELECT_OBRA = `
  *,
  obra_empresa ( *, empresas ( * ) ),
  obra_persona (
    *,
    personas ( * ),
    empresas ( id, razon_social, nombre_comercial ),
    comercial_comisiones ( id, porcentaje, activo )
  )
`;

export async function getEmpresas(): Promise<Empresa[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("empresas")
    .select("*")
    .eq("activo", true)
    .order("razon_social");

  if (error) throw error;
  return data;
}

export async function getPersonas(): Promise<PersonaConEmpresa[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("personas")
    .select("*, empresas ( id, razon_social, nombre_comercial )")
    .eq("activo", true)
    .order("apellido")
    .order("nombre");

  if (error) throw error;
  return data;
}

export async function getObras(): Promise<ObraConRelaciones[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("obras")
    .select(SELECT_OBRA)
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data;
}

export async function getFuentes(): Promise<Fuente[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("comercial_fuentes")
    .select("*")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data;
}

// `usuarios` se desambigua por FK: comercial_prospectos apunta dos veces a
// usuarios (responsable y creador) y sin el nombre del constraint PostgREST no
// sabe cuál embeber.
export async function getProspectos(): Promise<ProspectoListado[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("comercial_prospectos")
    .select(
      `*,
       obras ( ${SELECT_OBRA} ),
       comercial_fuentes ( id, nombre ),
       usuarios!comercial_prospectos_responsable_id_fkey ( id, nombre )`
    )
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data as unknown as ProspectoListado[];
}
