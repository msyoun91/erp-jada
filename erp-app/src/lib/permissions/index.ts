import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

export const getUserSubmodulos = cache(async (): Promise<string[]> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  const { data } = await supabase
    .from("usuario_submodulos")
    .select("submodulos(codigo)")
    .eq("usuario_id", user.id)
    .eq("activo", true);

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
    .select("submodulos(codigo, modulo, tipo, nombre, orden)")
    .eq("usuario_id", user.id)
    .eq("activo", true);

  return (data ?? [])
    .map((row) => row.submodulos)
    .filter(
      (s): s is NonNullable<typeof s> =>
        s !== null && s.modulo === modulo && s.tipo === "vista"
    )
    .sort((a, b) => a.orden - b.orden);
}
