import { createClient } from "@/lib/supabase/server";
import type { DashboardData } from "./types";

export async function getDashboardData(): Promise<DashboardData> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("usuarios")
    .select("id", { count: "exact", head: true })
    .eq("activo", true);

  return { totalUsuariosActivos: count ?? 0 };
}

export async function getWidgetPrefs(): Promise<Record<string, boolean>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return {};

  const { data, error } = await supabase
    .from("usuario_widgets")
    .select("widget_id, visible")
    .eq("usuario_id", user.id);

  if (error) throw error;
  return Object.fromEntries(data.map((r) => [r.widget_id, r.visible]));
}
