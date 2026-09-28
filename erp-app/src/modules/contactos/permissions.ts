import { tienePermiso } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export function puedeVerContactos() {
  return tienePermiso("contactos_ver");
}

export function puedeAdministrar() {
  return tienePermiso("contactos_administrar");
}

// Espejo de CO007 para mostrar "Desactivar": el delegador de su equipo, quien
// la cargó si no tiene equipo, el admin. La regla la hace valer la base.
export async function desactivaEmpresa(empresa: { equipo_id: string | null; creado_por: string }, yo: string) {
  if (await puedeAdministrar()) return true;
  if (empresa.equipo_id === null) return empresa.creado_por === yo;
  if (!(await tienePermiso("usuarios_delegar"))) return false;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("mi_equipo");
  if (error) throw error;
  return data === empresa.equipo_id;
}

export function puedeAprobar() {
  return tienePermiso("contactos_aprobar");
}
