import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

export const getUserSubmodulos = cache(async (): Promise<string[]> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  // `usuarios!inner(activo)` espeja el chequeo que `tiene_permiso()` hace en
  // SQL: un usuario desactivado no tiene permisos. Sin esto las actions que
  // usan `service_role` (crear usuario, asignar permisos) quedarían sin
  // barrera — el service_role no pasa por RLS, así que este chequeo es la
  // única que tienen.
  const { data } = await supabase
    .from("usuario_submodulos")
    .select("submodulos(codigo), usuarios!inner(activo)")
    .eq("usuario_id", user.id)
    .eq("activo", true)
    .eq("usuarios.activo", true);

  return (data ?? [])
    .map((row) => row.submodulos?.codigo)
    .filter((codigo): codigo is string => Boolean(codigo));
});

export async function tienePermiso(codigo: string): Promise<boolean> {
  const codigos = await getUserSubmodulos();
  return codigos.includes(codigo);
}

export async function getVistasDeModulo(modulo: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  const { data } = await supabase
    .from("usuario_submodulos")
    .select("submodulos(codigo, modulo, tipo, nombre, orden), usuarios!inner(activo)")
    .eq("usuario_id", user.id)
    .eq("activo", true)
    .eq("usuarios.activo", true);

  return (data ?? [])
    .map((row) => row.submodulos)
    .filter(
      (s): s is NonNullable<typeof s> =>
        s !== null && s.modulo === modulo && s.tipo === "vista"
    )
    .sort((a, b) => a.orden - b.orden);
}
