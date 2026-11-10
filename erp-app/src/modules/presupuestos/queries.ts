import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";

type Presupuesto = Database["public"]["Tables"]["presupuestos"]["Row"];
type Autorizacion = Database["public"]["Tables"]["presupuestos_autorizaciones"]["Row"];

export type PresupuestoResumen = Pick<Presupuesto, "id" | "codigo" | "nombre" | "estado"> & { obra: string };

// La RLS decide cuáles: los de las obras que quien llama ve o, con `presupuestos_administrar`, todos.
export async function getPresupuestos(): Promise<PresupuestoResumen[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos")
    .select("id, codigo, nombre, estado, obra:obras!inner(nombre)")
    .eq("activo", true)
    .order("numero", { ascending: false });
  if (error) throw error;
  return data.map(({ obra, ...p }) => ({ ...p, obra: obra.nombre }));
}

export type Pedido = Pick<Autorizacion, "id" | "tipo" | "estado" | "motivo" | "pedido_por" | "resuelto_por" | "resuelto_en" | "created_at"> & {
  texto: string;
  version: { id: string; numero: number; estado: Database["public"]["Enums"]["estado_version_presupuesto"] };
  presupuesto: Pick<Presupuesto, "id" | "codigo" | "nombre" | "obra_id">;
};

const PEDIDO = `id, tipo, estado, motivo, pedido, pedido_por, resuelto_por, resuelto_en, created_at,
  version:presupuestos_versiones!inner(id, numero, estado, activo,
    presupuesto:presupuestos!presupuestos_versiones_presupuesto_id_fkey!inner(id, codigo, nombre, obra_id, activo))`;

async function getPedidos(estadoVersion: Pedido["version"]["estado"]): Promise<Pedido[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos_autorizaciones")
    .select(PEDIDO)
    .eq("version.estado", estadoVersion)
    .eq("version.activo", true)
    .eq("version.presupuesto.activo", true)
    .order("created_at");
  if (error) throw error;
  return data.map(({ pedido, version: { presupuesto, ...version }, ...a }) => ({
    ...a,
    texto: (pedido as { texto: string }).texto.replace(/^autorización [^:]+: /, ""),
    version,
    presupuesto,
  }));
}

// Lo que espera a quien llama: los pedidos al jefe pendientes, de las obras donde puede autorizar.
export async function getEsperan(): Promise<Pedido[]> {
  const pendientes = (await getPedidos("en_revision")).filter((p) => p.tipo === "comercial" && p.estado === "pendiente");
  const supabase = await createClient();
  const obras = [...new Set(pendientes.map((p) => p.presupuesto.obra_id))];
  const puede = await Promise.all(
    obras.map(async (obra) => {
      const { data, error } = await supabase.rpc("presupuestos_puede_autorizar", { p_tipo: "comercial", p_obra: obra });
      if (error) throw error;
      return data;
    })
  );
  return pendientes.filter((p) => puede[obras.indexOf(p.presupuesto.obra_id)]);
}

// Las versiones que volvieron a borrador por una devolución y todavía no se pidieron de nuevo:
// pedir otra vez crea filas más nuevas, y retirar ese pedido no las vuelve a mostrar.
export async function getDevueltas(): Promise<Pedido[]> {
  const pedidos = await getPedidos("borrador");
  const ultima = new Map<string, string>();
  for (const p of pedidos) ultima.set(p.version.id, p.created_at);
  return pedidos.filter((p) => p.estado === "devuelta" && p.created_at === ultima.get(p.version.id));
}

// id de usuario → nombre, de lo que se ve en Obras: quien pide o devuelve trabaja la obra.
export async function getNombres(): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_nombres");
  if (error) throw error;
  return Object.fromEntries(data.map((n) => [n.id, n.nombre]));
}
