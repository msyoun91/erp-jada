import { getUserSubmodulos } from "@/lib/permissions";
import { WIDGETS, type WidgetDefinicion } from "./types";

export async function getWidgetsPermitidos(): Promise<WidgetDefinicion[]> {
  const codigos = await getUserSubmodulos();
  const modulosVisibles = new Set(codigos.map((c) => c.split("_")[0]));
  return WIDGETS.filter((w) => modulosVisibles.has(w.moduloRequerido));
}
