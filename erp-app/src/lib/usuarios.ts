import { createClient } from "@/lib/supabase/server";

// Quién soy y quiénes están activos no es de ningún módulo: tareas lo usa para
// asignar, comercial para elegir responsable de un prospecto. La RLS de
// `usuarios` decide qué devuelve el SELECT, no esta función.
export type UsuarioBasico = { id: string; nombre: string };

export async function getUsuarioActualId(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}

export async function getUsuariosActivos(): Promise<UsuarioBasico[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("usuarios")
    .select("id, nombre")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data;
}
