import type { Moneda } from "@/lib/monedas";
import { createClient } from "@/lib/supabase/server";
import type { Categoria, Color, Costo, Insumo, TipoCatalogo, TipoInsumo } from "./types";

export async function getCategorias(tipo: TipoCatalogo): Promise<Categoria[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("catalogo_categorias")
    .select("id, nombre, activo")
    .eq("tipo", tipo)
    .order("nombre");
  if (error) throw error;
  return data;
}

export async function getColores(): Promise<Color[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("catalogo_colores").select("id, nombre, activo").order("nombre");
  if (error) throw error;
  return data;
}

// Los costos los filtra la base: sin `catalogo_costos` (o `catalogo_fijos_editar` para un servicio),
// `catalogo_costos_vigentes` no trae ninguno.
export async function getInsumos(tipo: TipoInsumo): Promise<Insumo[]> {
  const supabase = await createClient();
  const [insumos, costos] = await Promise.all([
    supabase
      .from("catalogo_insumos")
      .select(
        "id, nombre, categoria_id, unidad, peso, espesor, con_color, activo, catalogo_variantes(id, color_id, activo)",
      )
      .eq("tipo", tipo)
      .order("nombre"),
    supabase.rpc("catalogo_costos_vigentes"),
  ]);
  if (insumos.error) throw insumos.error;
  if (costos.error) throw costos.error;

  const porVariante = new Map<string, Costo>(
    costos.data.map((c) => [c.variante_id, { costo: c.costo, moneda: c.moneda, desde: c.created_at }]),
  );
  return insumos.data.map(({ catalogo_variantes, ...i }) => ({
    ...i,
    variantes: catalogo_variantes.map((v) => ({ ...v, costo: porVariante.get(v.id) ?? null })),
  }));
}

export async function getMonedaPrincipal(): Promise<Moneda> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("monedas_principal_actual");
  if (error) throw error;
  return data;
}
